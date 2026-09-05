# meta-x570d4u

Board support for the **ASRock Rack X570D4U-2L2T** running OpenBMC, as used with a
Supermicro PWS-441P-1H power supply in a Chenbro RM238 chassis.

Upstream `entity-manager` ships `asrock/x470d4u.json` but nothing for the X570D4U, so
out of the box this board reports **no sensors at all**. This layer adds the sensor
configuration plus a few small services for things the device tree does not cover.

See [docs/REFERENCES.md](docs/REFERENCES.md) for the specifications behind the
workarounds below.

## What this adds

| Area | What |
|---|---|
| Voltages | 13 ADC rails. Host-only rails carry `PowerState: "On"` so they read `nan` instead of alarming while the host is off. |
| Temperatures | W83773G (i2c-1 0x4c), front panel TMP75 (i2c-0 0x4d), on-DIMM JC42 (i2c-7 0x1a/0x1b) |
| PSU | PMBus at i2c-2 0x3c, FRU EEPROM at 0x38, matched by the PSU's own FRU |
| Battery | VBAT sense enable |
| Kernel | `CONFIG_SENSORS_JC42` for the on-DIMM sensors |

## The non-obvious bits

**The PSU fan runs flat out unless you encode `FAN_COMMAND_1` its way.** The PMBus
AC/DC Server Power profile fixes that command's linear exponent at N=0, while the
kernel `pmbus` driver writes ordinary LINEAR11 with a *computed* exponent. A target of
30 therefore leaves as `0xdbc0`; the PSU ignores the exponent, reads mantissa 960, and
treats it as 960% duty -- pinning the fan near 13000 RPM. Because the command can only
ever *increase* fan speed, it never recovers on its own and `CLEAR_FAULTS` does not
help. `psu-fan-release` re-asserts a correctly encoded floor, and publishes the true
speed and duty as ExternalSensors because the kernel's own readings are wrong in both
directions. Note it must run as a **guard**, not a one-shot: `psusensor` rewrites the
bad value whenever it re-creates the PSU sensors, which includes any entity-manager
config republish.

**`fru-device` must be kept away from the PSU's PMBus address.** It probes for FRU
EEPROMs using `i2c_smbus_write_byte` to set a read offset; on a PMBus device that byte
*is* a command, so probing injects arbitrary PMBus commands into the PSU. Hence
`blacklist.json`. The PSU's real FRU EEPROM at 0x38 is deliberately left un-blacklisted.

**Do not instantiate the pmbus device yourself.** `psusensor` creates *and deletes*
that device. A second owner makes them fight, and the device ends up repeatedly torn
down, taking the PSU sensors with it.

**VBAT reads ~0 mV until a GPIO is asserted.** The board gates the divider behind
`output-hwm-vbat-enable`, which OpenBMC never claims. `vbat-enable` holds it, after
which ADC channel 9 reads a sane battery voltage.

**entity-manager caches its parsed configuration** in `/var/configuration/system.json`
and does *not* re-read the config files on a plain restart. When editing configs,
remove that file first or your changes will appear to be silently ignored.

## Known gaps

* No UID/identify LED. The locator is a hardware latch: the BMC can only *read* state
  via `input-locatorled-n` and pulse `control-locatorbutton-n` to toggle it, so a
  `gpio-leds` node will not work and `phosphor-led-manager` has no LED to bind.
* No host inventory (DIMM part numbers, PCIe devices). That needs the BIOS to push
  SMBIOS to the BMC, which this board's firmware does not appear to do.
* The SAS backplane is not reachable from the BMC; it manages its own fans.
