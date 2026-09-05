# Board and PSU configuration for the ASRock Rack X570D4U-2L2T.
#
# Upstream entity-manager ships asrock/x470d4u.json but nothing for the X570D4U,
# so no sensors are detected on this board without these. The PSU config matches
# a Supermicro PWS-441P-1H by its own FRU; its PMBus interface is at 0x3c on the
# PSU SMBus (i2c-2), with the FRU EEPROM at 0x38.
#
# blacklist.json keeps fru-device away from 0x3c. fru-device probes for FRU
# EEPROMs using i2c_smbus_write_byte to set a read offset; on a PMBus device that
# byte IS a command, so probing the PSU injects arbitrary PMBus commands into it.
# On this board that pins the PSU fan at ~13000 RPM whenever the host is powered on.
# 0x38 (the PSU's real FRU EEPROM) is deliberately NOT blacklisted.

FILESEXTRAPATHS:prepend:x570d4u := "${THISDIR}/${PN}:"

SRC_URI:append:x570d4u = " \
    file://x570d4u.json \
    file://pws_441p_1h.json \
    file://blacklist.json \
    "

do_install:append:x570d4u() {
    install -d ${D}${datadir}/entity-manager/configurations/asrock
    install -d ${D}${datadir}/entity-manager/configurations/supermicro
    install -m 0644 ${UNPACKDIR}/x570d4u.json \
        ${D}${datadir}/entity-manager/configurations/asrock/
    install -m 0644 ${UNPACKDIR}/pws_441p_1h.json \
        ${D}${datadir}/entity-manager/configurations/supermicro/
    install -m 0644 ${UNPACKDIR}/blacklist.json \
        ${D}${datadir}/entity-manager/blacklist.json
}
