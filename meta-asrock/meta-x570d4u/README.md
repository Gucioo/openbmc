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
| PSU | Full PMBus telemetry, PSU in Redfish inventory, fan held at a sane floor |
| Power | `total_power` from the PSU's true AC input, surfaced as `PowerConsumedWatts` |
| Battery | VBAT, via a sense-enable GPIO OpenBMC otherwise never asserts |
| Identify LED | Read-only mirror of the front panel latch, as Redfish `LocationIndicatorActive` |
| Web UI | Dark theme |
| Fan control | Configured but **untested** -- see below |

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

## Known gaps

* **Fan control is untested and ships masked.** Nothing is connected to the motherboard fan
  headers on this system -- all chassis fans are on a Chenbro backplane that regulates them
  itself -- and the `/xyz/openbmc_project/control/fanpwm/*` objects phosphor-fan drives are
  only created by fansensor once a real fan is detected. With empty headers the control loop
  retries that lookup every two seconds forever, which floods an 8 MB RAM-backed journal, so
  `phosphor-fan-control@0` is masked; monitor and presence stay enabled. Once a fan is on a
  header:

  ```
  systemctl unmask phosphor-fan-control@0.service
  systemctl start  phosphor-fan-control@0.service
  ```

  The config is adapted from Renze Nicolai's port; see the bbappend for the three changes
  that were required.
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
