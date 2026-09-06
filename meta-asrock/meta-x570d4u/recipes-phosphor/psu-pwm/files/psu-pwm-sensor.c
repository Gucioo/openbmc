/*
 * Publish the PSU fan duty cycle as a proper percent sensor.
 *
 * The board's own fan PWMs read as "%" in Redfish because dbus-sensors' PwmSensor puts
 * them under /xyz/openbmc_project/sensors/fan_pwm/ with Unit.Percent. That code path is
 * driven off a hwmon pwmN file, and the PSU has none -- its pmbus hwmon exposes
 * fan1_target but no pwm1 -- so the duty has to be read over PMBus instead.
 *
 * An entity-manager ExternalSensor cannot fill the gap: it derives its object namespace
 * solely from "Units" via sensor_paths::getPathForUnits, and while "Percent" is in that
 * allowlist it maps to /xyz/openbmc_project/sensors/percent/, which bmcweb's sensor
 * collection does not enumerate. Such a sensor is correctly labelled and completely
 * invisible. No units value maps to fan_pwm. Hence this daemon, which owns the object
 * directly.
 *
 * psu-fan-release already talks PMBus to hold the fan floor, so it writes the current duty
 * to a small state file and this only has to render it on D-Bus -- one PMBus reader, no
 * second bus master.
 */

#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <systemd/sd-bus.h>

#define BUS_NAME    "xyz.openbmc_project.PsuPwmSensor"
#define OBJ_PATH    "/xyz/openbmc_project/sensors/fan_pwm/PSU0_Fan1_PWM"
#define SENSOR_ROOT "/xyz/openbmc_project/sensors"
#define VALUE_IFACE "xyz.openbmc_project.Sensor.Value"
#define ASSOC_IFACE "xyz.openbmc_project.Association.Definitions"
#define UNIT_PCT    "xyz.openbmc_project.Sensor.Value.Unit.Percent"

/* bmcweb reaches a chassis' sensors through the "all_sensors" association. */
#define CHASSIS_PATH \
    "/xyz/openbmc_project/inventory/system/board/ASRock_Rack_X570D4U_2L2T"

#define STATE_FILE "/run/psu0_fan1_pwm"
#define POLL_USEC  (5000000ULL)

static double value = NAN;

static int prop_get(sd_bus *bus, const char *path, const char *iface,
                    const char *prop, sd_bus_message *reply, void *userdata,
                    sd_bus_error *err)
{
    (void)bus; (void)path; (void)iface; (void)userdata; (void)err;

    if (strcmp(prop, "Value") == 0)
        return sd_bus_message_append(reply, "d", value);
    if (strcmp(prop, "MaxValue") == 0)
        return sd_bus_message_append(reply, "d", 100.0);
    if (strcmp(prop, "MinValue") == 0)
        return sd_bus_message_append(reply, "d", 0.0);
    if (strcmp(prop, "Unit") == 0)
        return sd_bus_message_append(reply, "s", UNIT_PCT);
    return -EINVAL;
}

static int assoc_get(sd_bus *bus, const char *path, const char *iface,
                     const char *prop, sd_bus_message *reply, void *userdata,
                     sd_bus_error *err)
{
    (void)bus; (void)path; (void)iface; (void)prop; (void)userdata; (void)err;
    return sd_bus_message_append(reply, "a(sss)", 1,
                                 "chassis", "all_sensors", CHASSIS_PATH);
}

static const sd_bus_vtable value_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_PROPERTY("Value", "d", prop_get, 0,
                    SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE),
    SD_BUS_PROPERTY("MaxValue", "d", prop_get, 0,
                    SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("MinValue", "d", prop_get, 0,
                    SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("Unit", "s", prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END,
};

static const sd_bus_vtable assoc_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_PROPERTY("Associations", "a(sss)", assoc_get, 0,
                    SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END,
};

/* NAN when the file is absent or unparseable, so the sensor reads "unavailable"
   rather than a stale duty if psu-fan-release stops. */
static double read_state(void)
{
    FILE *f = fopen(STATE_FILE, "r");
    if (f == NULL)
        return NAN;

    double v = NAN;
    if (fscanf(f, "%lf", &v) != 1)
        v = NAN;
    fclose(f);

    if (!isfinite(v) || v < 0.0 || v > 100.0)
        return NAN;
    return v;
}

int main(void)
{
    sd_bus *bus = NULL;
    int r = sd_bus_default_system(&bus);
    if (r < 0) {
        fprintf(stderr, "sd_bus_default_system: %s\n", strerror(-r));
        return 1;
    }

    /* Without an object manager the mapper never discovers the sensor. */
    r = sd_bus_add_object_manager(bus, NULL, SENSOR_ROOT);
    if (r < 0) {
        fprintf(stderr, "add_object_manager: %s\n", strerror(-r));
        return 1;
    }

    r = sd_bus_add_object_vtable(bus, NULL, OBJ_PATH, VALUE_IFACE, value_vtable,
                                 NULL);
    if (r < 0) {
        fprintf(stderr, "add value vtable: %s\n", strerror(-r));
        return 1;
    }

    r = sd_bus_add_object_vtable(bus, NULL, OBJ_PATH, ASSOC_IFACE, assoc_vtable,
                                 NULL);
    if (r < 0) {
        fprintf(stderr, "add association vtable: %s\n", strerror(-r));
        return 1;
    }

    r = sd_bus_request_name(bus, BUS_NAME, 0);
    if (r < 0) {
        fprintf(stderr, "request name %s: %s\n", BUS_NAME, strerror(-r));
        return 1;
    }

    value = read_state();

    for (;;) {
        double now = read_state();

        /* NAN != NAN, so compare the unavailable case explicitly. */
        int changed = (isnan(now) != isnan(value)) ||
                      (!isnan(now) && !isnan(value) && now != value);
        if (changed) {
            value = now;
            sd_bus_emit_properties_changed(bus, OBJ_PATH, VALUE_IFACE, "Value",
                                           NULL);
        }

        for (;;) {
            r = sd_bus_process(bus, NULL);
            if (r <= 0)
                break;
        }
        sd_bus_wait(bus, POLL_USEC);
    }

    return 0;
}
