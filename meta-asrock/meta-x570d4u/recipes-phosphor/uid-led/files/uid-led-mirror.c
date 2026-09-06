// Mirror the X570D4U's identify (UID) LED state onto D-Bus.
//
// This board does not let the BMC drive its identify LED. Unlike e.g. altrad8, which has a
// dedicated "led-identify-n" output, the X570D4U exposes only:
//
//   input-locatorled-n     (gpiochip0 line 0)  - reads the latch state, active low
//   control-locatorbutton-n(gpiochip0 line 22) - emulates a front panel button press
//
// Asserting line 22 from the BMC reliably wedges the kernel a few seconds later (reproduced
// with both drive modes and with 50 ms and 600 ms pulses), while the physical button is
// entirely reliable. So this daemon is deliberately READ ONLY: it publishes the LED state
// that bmcweb renders as Redfish LocationIndicatorActive, and the front panel button remains
// the only way to change it. Writes to Asserted are rejected.
//
// It holds a single GPIO request for its lifetime rather than opening the line per read,
// avoiding repeated claim/release of the pin.

#include <gpiod.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <systemd/sd-bus.h>
#include <systemd/sd-event.h>

// bmcweb hardcodes this service name when reading the identify group, so we must own it.
// phosphor-led-manager would normally, but it has no LED group config on this board and
// never reaches the point of taking the name -- the unit is masked in favour of this.
#define BUS_NAME  "xyz.openbmc_project.LED.GroupManager"
#define OBJ_PATH  "/xyz/openbmc_project/led/groups/enclosure_identify"
#define IFACE     "xyz.openbmc_project.Led.Group"
#define CHIP      "gpiochip0"
#define LINE      0
#define POLL_USEC (1000000ULL)

// bmcweb resolves LocationIndicatorActive per chassis: it looks up
// "<chassis inventory path>/identifying" and expects it to point at an LED group under
// /xyz/openbmc_project/led/groups (see redfish-core/lib/led.hpp, getLedGroupPath). The
// chassis object is owned by entity-manager, which has no way to declare that association,
// so we publish it from this side: forward "identified_by" on the group, reverse
// "identifying" on the chassis. Override the chassis path with argv[1] if the board name
// ever changes.
#define DEFAULT_CHASSIS \
    "/xyz/openbmc_project/inventory/system/board/ASRock_Rack_X570D4U_2L2T"

static const char *chassis_path = DEFAULT_CHASSIS;

static int assoc_get(sd_bus *b, const char *path, const char *iface, const char *prop,
                     sd_bus_message *reply, void *ud, sd_bus_error *err)
{
    (void)b; (void)path; (void)iface; (void)prop; (void)ud; (void)err;
    int r = sd_bus_message_open_container(reply, 'a', "(sss)");
    if (r < 0) return r;
    r = sd_bus_message_append(reply, "(sss)", "identified_by", "identifying", chassis_path);
    if (r < 0) return r;
    return sd_bus_message_close_container(reply);
}

static const sd_bus_vtable assoc_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_PROPERTY("Associations", "a(sss)", assoc_get, 0,
                    SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END
};

static struct gpiod_line *line;
static bool asserted;

static int prop_get(sd_bus *b, const char *path, const char *iface, const char *prop,
                    sd_bus_message *reply, void *ud, sd_bus_error *err)
{
    (void)b; (void)path; (void)iface; (void)prop; (void)ud; (void)err;
    return sd_bus_message_append(reply, "b", asserted);
}

// The LED is owned by a board latch; the BMC has no safe way to drive it.
static int prop_set(sd_bus *b, const char *path, const char *iface, const char *prop,
                    sd_bus_message *value, void *ud, sd_bus_error *err)
{
    (void)b; (void)path; (void)iface; (void)prop; (void)value; (void)ud;
    return sd_bus_error_set_const(err, SD_BUS_ERROR_NOT_SUPPORTED,
        "Identify LED is controlled by the front panel button on this board");
}

static const sd_bus_vtable vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_WRITABLE_PROPERTY("Asserted", "b", prop_get, prop_set, 0,
                             SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE),
    SD_BUS_VTABLE_END
};

static int on_tick(sd_event_source *s, uint64_t usec, void *userdata)
{
    sd_bus *bus = userdata;
    int v = gpiod_line_get_value(line);
    if (v >= 0) {
        bool now = (v == 0);            // active low: 0 means the LED is lit
        if (now != asserted) {
            asserted = now;
            sd_bus_emit_properties_changed(bus, OBJ_PATH, IFACE, "Asserted", NULL);
        }
    }
    sd_event_source_set_time(s, usec + POLL_USEC);
    sd_event_source_set_enabled(s, SD_EVENT_ONESHOT);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc > 1) chassis_path = argv[1];
    struct gpiod_chip *chip = gpiod_chip_open_by_name(CHIP);
    if (!chip) { fprintf(stderr, "uid-led-mirror: cannot open %s\n", CHIP); return 1; }
    line = gpiod_chip_get_line(chip, LINE);
    if (!line || gpiod_line_request_input(line, "uid-led-mirror") < 0) {
        fprintf(stderr, "uid-led-mirror: cannot request line %d as input\n", LINE);
        return 1;
    }
    int v = gpiod_line_get_value(line);
    asserted = (v == 0);

    sd_bus *bus = NULL;
    sd_event *event = NULL;
    if (sd_bus_default_system(&bus) < 0) return 1;
    if (sd_event_default(&event) < 0) return 1;
    if (sd_bus_add_object_vtable(bus, NULL, OBJ_PATH, IFACE, vtable, NULL) < 0) return 1;
    // The OpenBMC ObjectMapper discovers objects through ObjectManager; without this,
    // bmcweb never finds the group and LocationIndicatorActive stays absent.
    if (sd_bus_add_object_manager(bus, NULL, "/xyz/openbmc_project/led") < 0) return 1;
    if (sd_bus_add_object_vtable(bus, NULL, OBJ_PATH,
            "xyz.openbmc_project.Association.Definitions", assoc_vtable, NULL) < 0)
        return 1;
    if (sd_bus_request_name(bus, BUS_NAME, 0) < 0) {
        fprintf(stderr, "uid-led-mirror: cannot take bus name %s\n", BUS_NAME);
        return 1;
    }
    if (sd_bus_attach_event(bus, event, SD_EVENT_PRIORITY_NORMAL) < 0) return 1;

    uint64_t now = 0;
    sd_event_now(event, CLOCK_MONOTONIC, &now);
    sd_event_add_time(event, NULL, CLOCK_MONOTONIC, now + POLL_USEC, 0, on_tick, bus);

    return sd_event_loop(event) < 0 ? 1 : 0;
}
