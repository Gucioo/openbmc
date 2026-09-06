# References

Documents used while bringing up this board. They are third-party copyrighted
material and are deliberately **not** mirrored here -- only linked, with a note on
which part actually mattered.

## PMBus

* **PMBus Specification Rev 1.2, Part I & Part II** -- System Management Interface
  Forum. <https://pmbus.org/specification-archives/>
  * Part II §7.1 *Linear Data Format*: an 11-bit two's complement mantissa with a
    5-bit two's complement exponent. This is the decode used for `READ_FAN_SPEED_1`.
  * Part II, `READ_FAN_SPEED_1` (90h): "The value returned is in RPM", in either
    Linear or DIRECT format -- the device's literature states which.

* **PMBus Application Profile for AC/DC Server Power Supplies, Rev 1.2**
  <https://pmbus.org/specification-archives/>
  * §12.1 `FAN_CONFIG_1_2` (3Ah): bit 7 fan present, bit 6 = 0 duty-cycle control.
  * §12.2 `FAN_COMMAND_1` (3Bh): **"can only increase the power supplies fan speed"**
    and **"the exponent N is fixed to a value of 0"**. This single sentence explains
    the fan behaviour this layer works around -- see `recipes-phosphor/psu/`.
  * §12.3 `READ_FAN_SPEED_1` (90h): returned in PMBus linear format.

## Supermicro PWS-441P-1H (the PSU this board was paired with)

* **PWS-441P-1H Quick Specification**
  <https://store.supermicro.com/us_en/pub/media/wysiwyg/productspecs/PWS-441P-1H/PWS-441P-1H_quick_spec.pdf>
  * Cooling: "4028 PWM Controlled Ball Bearing Fan" -- a 40x28mm fan, so the ~13300 RPM
    seen at full duty is normal for the part.
  * Remote management: PMBus 1.2 / SMBus, via a 380 mm SMBus/I2C cable.

* **Supermicro IPMICFG User's Guide**
  <https://www.supermicro.com/wdl/utility/IPMICFG/IPMICFG_UserGuide.pdf>
  * The `-pminfo` example is for a PWS-441P-1H at SlaveAddress **78h** (7-bit 0x3C),
    and `-psfruinfo` at **70h** (7-bit 0x38). That is the address split this layer uses.
  * Its example output shows 42 W / 43 C / **224 RPM**, which is the reference point
    showing that a fan pinned near 13000 RPM is abnormal, not merely loud.

## Chassis

* **Chenbro RM238 series user manual**
  <https://gzhls.at/blob/ldb/d/2/3/2/62644950ba85aa48a8451ba4d21d598949f3.pdf>
  * The 380-23810-3000A3 backplane is passive, with temperature monitoring and smart
    fan control built into the backplane itself -- it is not reachable from the BMC.
    The front panel, however, provides the temperature sensor this layer reads at
    i2c-0 0x4d.

## OpenBMC source referenced

* `entity-manager` -- `fru-device` probes FRU EEPROMs with `i2c_smbus_write_byte`;
  on a PMBus device that byte is a command. Hence `blacklist.json`.
* `dbus-sensors` -- `psusensor` creates *and deletes* the i2c device itself; a second
  owner makes them fight.
* Linux `drivers/hwmon/pmbus/pmbus_core.c` -- encodes fan targets as LINEAR11 with a
  computed exponent, which is what disagrees with the N=0 profile above.
* `dbus-sensors` -- `hwmontempsensor` likewise creates the TMP75/JC42 devices. The rule
  generalises: if a dbus-sensors daemon handles a device class, do not also bind it from
  systemd.
* `dbus-sensors` -- `HwmonTempSensor`/`PSUSensor` assign the `Name`, `Name1`, `Name2`...
  keys in **hwmon index order**, not in the order of the `Labels` array. There is no way
  to bind a name to a specific label, which is why the NCT6779 is left unconfigured.
* `bmcweb` -- `redfish-core/lib/led.hpp`: `getIndicatorLedState`/`getLocationIndicatorActive`
  call `xyz.openbmc_project.LED.GroupManager` **by hardcoded service name**, on
  `/xyz/openbmc_project/led/groups/enclosure_identify`, reading the `Asserted` property of
  `xyz.openbmc_project.Led.Group`.
* `bmcweb` -- `redfish-core/lib/chassis.hpp`: `hasIndicatorLedInterfaces()` gates the whole
  lookup on the chassis implementing `Inventory.Item.Chassis`, `Item.Panel` or
  `Item.Board.Motherboard`, and finds the group through an `identifying` association.
  A chassis without one of those interfaces silently reports no identify LED.
* `bmcweb` -- `meson.options`: `redfish-allow-deprecated-power-thermal` is off by default,
  which removes `/redfish/v1/Chassis/<id>/Power`. webui-vue still reads that endpoint for
  its Overview and Power pages, so the option is enabled here.
* `bmcweb` -- `meson.options`: the `vm-nbdproxy` feature is commented out upstream
  ("Disable NBD proxy support until it is fixed"), so Virtual Media has no working
  backend regardless of the web UI.
* `bmcweb` -- `redfish-core/lib/power_supply.hpp` never populates `PowerInputWatts`, which
  is what webui-vue renders as a PowerSupply's "Power input".
* `bmcweb` -- static file routes are enumerated once at startup, so files added under
  `/usr/share/www` need a bmcweb restart before they are served.
* `entity-manager` -- caches its parsed configuration in `/var/configuration/system.json`
  and serves that on restart instead of re-reading the config directory.
* `phosphor-led-manager` -- provides the `LED.GroupManager` name, but only when it has an
  LED configuration; with none, the unit exits and the name is free.

## Redfish host interface (why there is no DIMM/CPU inventory)

The stock ASRock firmware does show DIMM and CPU inventory, so the BIOS is publishing
SMBIOS -- but through an **AMI/ASRock OEM Redfish Host Interface**, reachable over the
BIOS-to-BMC USB NIC and exposed at OEM endpoints under `.../Oem/Ami` (the `asrr_hi`
service in the stock image). It is neither MDR V2 nor the IPMI blob transfer that
`smbios-mdr` consumes, so enabling `smbios-mdr` alone would leave it with nothing to read.

## Prior work on this board family

* **Renze Nicolai -- OpenBMC on the ASRock Rack X570D4U**
  <https://nicolaielectronics.nl/blog/openbmc-x570d4u/> and
  <https://github.com/renzenicolai/openbmc>
  Source of the original sensor bring-up approach and of the fan-control configuration
  adapted in `recipes-phosphor/fans/`.
* **Mrkvak -- homelab** <https://github.com/Mrkvak/homelab>
  Notes on running a Supermicro PSU on an ASRock Rack board, including the LTC4316
  address-translator approach that this system deliberately does *not* use (the
  translator was removed; everything here talks to the PSU at its native addresses).
* `dbus-sensors` -- `src/fan/FanMain.cpp`: the PWM object is created only when the fan's
  entity-manager config has a `Connector` sub-interface carrying `Pwm`. entity-manager
  builds that from `BindConnector` (`perform_scan.cpp:applyBindExposeAction` inlines the
  expose whose `Name` matches, under the key after "Bind"). Without it an `AspeedFan`
  yields a tach sensor and no PWM, and phosphor-fan-control spins on a failed lookup.
* `dbus-sensors` -- `src/PwmSensor.cpp`: `targetIfaceMax = sysPwmMax = 255`, so
  `Control.FanPwm`'s `Target` is raw PWM 0-255, while the `Sensor.Value` view of the same
  PWM is a percentage. Default object name is `Pwm_<n+1>` unless `PwmName` overrides it.
* OpenBMC rootfs layout -- the running filesystem is an overlay: read-only squashfs at
  `/run/initramfs/ro`, writable JFFS2 upper layer at `/run/initramfs/rw/cow`. A firmware
  update rewrites the squashfs but not the read-write volume, so any file written to `/usr`
  on a live BMC outlives every subsequent flash and silently shadows the image's copy.
* Linux `arch/arm/boot/dts/aspeed/aspeed-bmc-asrock-x570d4u.dts` -- the fan tach channel
  assignments are wrong for this board. Tach channel 3 is never enabled, so the FAN4 header
  reports no tachometer at all, and the primary channels for FAN5 and FAN6 are swapped.
  Patched in `recipes-kernel/linux/`. The `reg` values (PWM channel) and the header names in
  the comments are correct; only `aspeed,fan-tach-ch` is wrong.
* Linux `drivers/pinctrl/aspeed/pinctrl-aspeed-g5.c` -- defines no TACH/TACHO pinmux groups
  at all, so tach pins need no pinctrl entry; enabling a channel in the device tree is
  sufficient.
* `phosphor-fan-presence` -- `monitor/tach_sensor.cpp:TachSensor::getRange()` computes the
  allowed band as `target * (100 -/+ deviation)/100 * factor + offset`, so `factor` and
  `offset` must match the fans actually fitted or every fan is reported faulty.
