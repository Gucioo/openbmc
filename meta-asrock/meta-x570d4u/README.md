# meta-x570d4u

Board support for the **ASRock Rack X570D4U-2L2T** running OpenBMC, as used with a
Supermicro PWS-441P-1H power supply in a Chenbro RM238 chassis.

Upstream `entity-manager` ships `asrock/x470d4u.json` but nothing for the X570D4U, so out
of the box this board reports **no sensors at all**. This layer adds the sensor
configuration, PSU support, a dark web UI, an identify-LED mirror and fan control.

See [docs/REFERENCES.md](docs/REFERENCES.md) for the specifications behind the workarounds.

## What works

| Area | Detail |
|---|---|
| Voltages | 13 ADC rails. Host-only rails carry `PowerState: "On"` so they read `nan` rather than alarming while the host is off. |
| Temperatures | W83773G (i2c-1 0x4c), front panel TMP75 (i2c-0 0x4d), on-DIMM JC42 (i2c-7 0x1a/0x1b) |
| PSU | Full PMBus telemetry, PSU in Redfish inventory, fan held at a sane floor, duty as a true percent sensor |
| Power | `total_power` from the PSU's true AC input, surfaced as `PowerConsumedWatts` |
| Battery | VBAT, via a sense-enable GPIO OpenBMC otherwise never asserts |
| Identify LED | Read-only mirror of the front panel latch, as Redfish `LocationIndicatorActive` |
| Web UI | Dark theme, login page included |
| Fan control | Six motherboard headers on a temperature curve, verified against real fans |

## How the fans are controlled

Six config files under `recipes-phosphor/fans/phosphor-fan/x570d4u/`, installed to
`/usr/share/phosphor-fan-presence/`:

| File | Role |
|---|---|
| `fans.json` | maps each fan to a zone and to its PWM target object |
| `zones.json` | per-zone floor, ceiling, power-on target, ramp timing |
| `groups.json` | named groups of D-Bus objects (the fans; the temperatures) |
| `events.json` | the temperature-to-speed curves |
| `monitor.json` | expected RPM per PWM, for fault detection |
| `presence.json` | how presence is decided (tach) |

All six headers (FAN1-FAN6, driving `pwm1`-`pwm6`) are in a single zone `0`. Two
temperatures feed it, each with its own curve; the zone runs at whichever asks for more:

* **CPU_Temp** -- flat 30% to 45 C, then ramping to 100% at 85 C
* **MB_Temp** -- flat 30% to 35 C, then ramping to 100% at 65 C

Floor is 77/255 (30%), ceiling 255, power-on target 128 (50%). Targets everywhere are raw
PWM 0-255, not percent. Speed only decreases after 30 s at a lower demand
(`decrease_interval`) and increases after 5 s (`increase_delay`), so it does not hunt.

### Header, PWM and tachometer mapping

Determined empirically -- drive one PWM to 255 with every other at 60, wait 25 s, and see
which tach responds. **The device tree groupings are not the wiring.** It pairs pwm channel
3 with tachs {4,11}, channel 4 with {6,13} and channel 5 with {5,12}, but the board is
wired otherwise:

| Header | PWM channel | sysfs | tach channel | sysfs | verified |
|---|---|---|---|---|---|
| FAN1 | 0 | `pwm1` | 0 | `fan1_input` | no fan fitted |
| FAN2 | 1 | `pwm2` | 1 | `fan2_input` | no fan fitted |
| FAN3 | 2 | `pwm3` | 2 | `fan3_input` | yes, 794 -> 2611 RPM |
| FAN4 | 3 | `pwm4` | 11? | `fan12_input` | **no tach response at all** |
| FAN5 | 4 | `pwm5` | 5 | `fan6_input` | yes, 700 -> 2347 RPM |
| FAN6 | 5 | `pwm6` | 4 | `fan5_input` | yes, 745 -> 2556 RPM |

The entity-manager `Index` on an `AspeedFan` is the tach channel, and `fanN_input` is
channel N-1. Two of these were wrong in the inherited configuration: FAN6 was on 6 and FAN4
on 4, the latter colliding with FAN6's real channel.

`monitor.json` models expected RPM as `target x (100 +/- deviation)/100 x factor + offset`.
The inherited `factor: 82` was for completely different fans -- at the 77 floor it expects
6314 RPM against an actual ~1030, so every fan would have been flagged faulty. Fitted to
the fans on this machine: `factor: 9`, `offset: 200`, `deviation: 30`, which brackets both
the floor (~1030 measured, 685-1101 allowed) and full speed (~2500 measured, 1806-3182).
Refit these if you fit different fans.

To retune, edit the `map` array of the relevant event in `events.json` -- each entry is
`{"value": <temperature C>, "target": <pwm 0-255>}` and the highest entry at or below the
current reading wins. Live-test without a rebuild by editing the copy in
`/usr/share/phosphor-fan-presence/control/` and restarting
`phosphor-fan-control@0.service`.

Adding a temperature source means adding a group in `groups.json` and a
`target_from_group_max` event in `events.json` with a **distinct `index`** -- the index
identifies that curve's contribution to the zone, and reusing one makes the curves
overwrite each other.

## The non-obvious parts

### The PSU fan runs flat out unless FAN_COMMAND is encoded its way

The PMBus AC/DC Server Power profile (§12.2) fixes `FAN_COMMAND_1`'s linear exponent at
**N=0**, while the kernel `pmbus` driver writes ordinary LINEAR11 with a *computed*
exponent. A target of 30 therefore leaves as `0xdbc0`; the PSU ignores the exponent, reads
mantissa 960, and treats it as 960% duty -- pinning the fan near 13000 RPM. Because the
command can only ever *increase* fan speed, it never recovers on its own and `CLEAR_FAULTS`
does not help.

`psu-fan-release` re-asserts a correctly encoded floor and publishes the true fan speed and
duty as ExternalSensors, because the kernel's own readings are wrong in both directions
(`fan1_target` reads 0 while the register holds 0x001e). It runs as a **guard, not a
one-shot**: psusensor rewrites the bad value whenever it re-creates the PSU sensors, which
includes any entity-manager config republish, not just at boot.

Measured on this unit: duty 0 stops the fan entirely (the tach still reports a phantom
~224 RPM, so do not trust it near zero), 20% -> 1248 RPM, 30% -> ~2900 RPM, 100% -> ~13300.

### Fan PWM objects come from a connector, not from fan detection

`phosphor-fan-control` drives `/xyz/openbmc_project/control/fanpwm/*`, and those objects are
created by dbus-sensors only when the entity-manager fan config carries a `Connector`. An
`AspeedFan` expose on its own gives a tach sensor and nothing else, so fan-control finds no
target, logs *"No service for ... Control.FanPwm"* and retries every two seconds forever --
roughly 43k lines a day into a RAM-backed journal that caps at 8 MB.

The fix is a `BindConnector` on each fan pointing at an `IntelFanConnector` expose that
declares `Pwm`, `Tachs` and optionally `PwmName`; entity-manager inlines the named expose as
a `.Connector` sub-interface, which is what dbus-sensors looks for. Note the default PWM
object name is `Pwm_<n+1>`, so `PwmName` is needed to get the `PWM1`-style names the
phosphor-fan config uses.

This is independent of whether a fan is plugged in -- the PWM outputs exist because the
sysfs `pwmN` files exist. On this board the tach indices skip 3 (`fan1,2,3,5,6,7_input`)
while the PWM channels do not, so `Tachs` runs 0,1,2,4,5,6 against `Pwm` 0..5.

`aspeed_pwm_tacho` exposes no `pwmN_enable`, so dbus-sensors logs one
*"Error read/write .../pwmN_enable"* per fan at startup. Harmless.

### Never instantiate i2c devices that a dbus-sensors daemon owns

`hwmontempsensor` creates the TMP75 and JC42 devices itself, and `psusensor` creates the
PSU's pmbus device. Adding a systemd unit to `echo <driver> <addr> > new_device` makes them
fight: the journal fills with "Failed to instantiate", and sensors appear and vanish. This
layer deliberately ships **no** such service -- only `vbat-enable`, which drives a GPIO.

### fru-device must be kept away from the PSU's PMBus address

It probes for FRU EEPROMs using `i2c_smbus_write_byte` to set a read offset; on a PMBus
device that byte *is* a command, so probing injects arbitrary PMBus commands into the PSU.
Hence `blacklist.json`. The PSU's real FRU EEPROM at 0x38 is deliberately not blacklisted.

### VBAT reads ~0 mV until a GPIO is asserted

The board gates the divider behind `output-hwm-vbat-enable`, which OpenBMC never claims.
`vbat-enable` holds it, after which ADC channel 9 reads the battery correctly.

### A percent sensor has to be published by hand

The board's PWMs read as `%` in Redfish because dbus-sensors' `PwmSensor` places them under
`/xyz/openbmc_project/sensors/fan_pwm/` with `Unit.Percent`. That path is driven off a hwmon
`pwmN` file, and the PSU has none -- its pmbus hwmon exposes `fan1_target` but no `pwm1` --
so the duty has to come over PMBus instead.

An entity-manager `ExternalSensor` cannot fill the gap. It derives its object namespace
solely from `Units` via `getPathForUnits`, and although `"Percent"` is in that allowlist it
maps to `/xyz/openbmc_project/sensors/percent/`, which bmcweb's sensor collection does not
enumerate -- the sensor would be correctly labelled and completely invisible. No units value
maps to `fan_pwm`. Using `"RPMS"` keeps it visible but labels a percentage as RPM.

Hence `psu-pwm-sensor`, which owns the object directly: `Sensor.Value` with `Unit.Percent`,
an object manager, and a `chassis`/`all_sensors` association so bmcweb finds it under the
chassis. `psu-fan-release` already talks PMBus to hold the floor, so it writes the duty to
`/run/psu0_fan1_pwm` and the daemon only renders it -- one PMBus reader, no second bus
master.

### Files copied to a running BMC permanently shadow the image

The rootfs is an overlay: a read-only squashfs under `/run/initramfs/ro` with a writable
JFFS2 upper layer at `/run/initramfs/rw/cow`. Anything written to `/usr` on a running BMC --
`scp`ing a config for a quick test, editing a JSON in place -- lands in the upper layer and
**keeps winning after every firmware update**, because a normal update rewrites the squashfs
but leaves the read-write volume alone.

The failure mode is quiet and misleading: a flash appears to succeed, the version string
changes, and the file you were testing still has your old test content. Verifying a flash by
reading files on the BMC can therefore confirm your own leftovers rather than the image.

Check with `find /run/initramfs/rw/cow/usr -type f`, and compare against
`/run/initramfs/ro/<same path>` before deleting anything -- a file that exists only in the
upper layer is not in the image at all. Delete stale copies from the `cow` directory
directly and reboot; deleting through the merged mount instead creates a whiteout device
that hides the image's copy just as effectively.

### entity-manager caches its parsed configuration

It serves `/var/configuration/system.json` and does **not** re-read the config files on a
plain restart, so edits appear to be silently ignored. Remove that file first, then restart
entity-manager and the sensor daemons.

### The identify LED is read-only by necessity

The BMC cannot drive this board's identify LED. Unlike `altrad8`, which has a dedicated
`led-identify-n` output, the X570D4U exposes only `input-locatorled-n` (read the latch) and
`control-locatorbutton-n` (emulate a button press). **Asserting the latter hangs the BMC**
-- reproduced with both drive modes and with 50 ms and 600 ms pulses, in three attempts out
of four, always about three seconds later. The physical button is entirely reliable. The
hardware watchdog recovers the BMC unaided in 90-140 s.

So `uid-led-mirror` publishes the state and rejects writes. Getting bmcweb to render it
needs four things that are only documented in its source
(`redfish-core/lib/led.hpp`, `chassis.hpp`):

1. a service publishing `xyz.openbmc_project.Led.Group` with `Asserted`;
2. `sd_bus_add_object_manager()`, or the ObjectMapper never discovers it;
3. that service must own the name **`xyz.openbmc_project.LED.GroupManager`**, which bmcweb
   hardcodes -- `phosphor-led-manager` never takes it here (no LED config), so it is masked;
4. an `identifying` association from the chassis to the group, published by the daemon since
   entity-manager cannot declare one -- **and** the chassis must implement one of
   `Item.Chassis` / `Item.Panel` / `Item.Board.Motherboard`, or bmcweb skips the lookup
   entirely with nothing logged.

### Dark mode

Bootstrap 5.3's dark theme is already compiled into webui-vue's CSS; it only needs
`data-bs-theme="dark"` on `<html>`. That alone leaves the main content light, because
webui-vue hardcodes light colours in ~28 component rules and forces `color:#161616!important`
on every label, which renders label text invisible on a dark surface.
`dark-overrides.css` restyles those. Selectors deliberately avoid Vue scoped-style hashes
(e.g. `[data-v-87dd92f4]`) because those change on every webui-vue rebuild. Note bmcweb
builds its static-file routes at startup, so restart it after adding files under
`/usr/share/www`.


The login page needs its own rules. `.login-container` and `.login-main` hardcode `#f4f4f4`
(and `#fff` again inside a `min-width:768px` media query) behind Vue scoped-hash selectors
like `.login-container[data-v-62114135]`, specificity (0,2,0). Matching the bare class with
`!important` beats both the hash selector and the media-query variant without depending on
a hash that changes every rebuild.

## Known gaps

* **FAN4's tachometer never reports.** Driving `pwm4` to full for 45 s moves none of the
  nine tach channels, with a fan connected to that header. Control still works (the PWM
  object exists regardless of tach), but the fan is invisible to monitoring. Its `Index` is
  set to 11, the channel the device tree pairs with that PWM, but this is unverified.
* **FAN1 and FAN2 are unpopulated on this system**, so their tach sensors read unavailable.
  Expected, and harmless now that the fan-not-present escalation events are gone.

* **NCT6779 Super I/O (i2c-1 0x2d) is deliberately not configured.** With the host on it
  binds and offers TSI0/TSI1 (AMD SB-TSI die temps), SYSTIN and AUXTIN1/2. But
  entity-manager assigns `Name`/`Name1`/... in hwmon index order rather than `Labels` order,
  so the names land on the wrong channels -- verified: a sensor named `CPU_Temp_TSI0` read
  41 while raw TSI0 was 35.75 and SYSTIN was 41.0. Shipping mislabelled temperatures is
  worse than shipping none. (`Labels` also wants the hwmon label *values*, e.g.
  `"TSI0_TEMP"`, not the `"temp13"` prefixes.) This is likely why the reference port left
  its NCT6779 names as placeholders `A`-`Z`.
* **No host inventory** (DIMM part numbers, PCIe devices). The BIOS does push SMBIOS, but
  over an ASRock/AMI OEM Redfish endpoint on the Host Interface -- see docs/REFERENCES.md.
  It is not MDR V2 or IPMI blob transfer, so `smbios-mdr` alone would sit idle.
* **No virtual media.** bmcweb still ships the code, but its `vm-nbdproxy` option is
  commented out upstream pending a backend daemon, so the Redfish resource is unreachable.
  This is why the web UI's Virtual Media page throws "Cannot read properties of undefined
  (reading 'ServiceEnabled')".
* **PowerSupply "Power input" shows `-- W`.** webui-vue reads `PowerInputWatts`, which this
  bmcweb never sets for any PowerSupply. The reading is available as the
  `PSU0 Total Input Power` sensor instead.
* The SAS backplane is not reachable from the BMC and manages its own fans.

## Build host requirements

Learned the hard way on Ubuntu 22.04:

* **GCC 12 or newer.** `nodejs-native` bundles `ada`, which uses C++20 `constexpr
  std::string`; libstdc++ only implements that from GCC 12, so GCC 11 fails `do_compile`
  with *"call to non-'constexpr' function ... basic_string"*.
* **Disk.** A full build does not fit comfortably in 100 GB. Add `INHERIT += "rm_work"` to
  `build/<machine>/conf/local.conf`.
