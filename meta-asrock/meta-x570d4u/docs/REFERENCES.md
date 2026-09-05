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
