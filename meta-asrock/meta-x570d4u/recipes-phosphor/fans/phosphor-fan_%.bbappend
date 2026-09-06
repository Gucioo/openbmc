# Fan control for the motherboard fan headers.
#
# ---------------------------------------------------------------------------------------
# UNTESTED. Nothing is currently connected to this board's fan headers -- all chassis fans
# are on a Chenbro backplane that regulates them itself -- so this configuration has never
# run against real hardware. It is here so control is ready when fans are plugged in. The
# tach sensors (AspeedFan FAN1-6 in the entity-manager config) and phosphor-fan's systemd
# units are already in place; note that the /xyz/openbmc_project/control/fanpwm/* objects
# this drives are only created by fansensor once a real fan is detected, so with empty
# headers the control loop has nothing to act on.
# ---------------------------------------------------------------------------------------
#
# Adapted from Renze Nicolai's X570D4U port (github.com/renzenicolai/openbmc-x570d4u), with
# three changes needed for this system:
#   * inventory paths rebased from .../system/chassis/x570d4u/... onto this board's
#     entity-manager path, .../system/board/ASRock_Rack_X570D4U_2L2T/...
#   * the thermal zone read TSI1_TEMP from the NCT6779 Super I/O. Those sensors are not
#     published here because entity-manager assigns their names in hwmon index order rather
#     than Labels order, so the names land on the wrong channels. The zone now reads
#     CPU_Temp and MB_Temp from the W83773G, both verified correct on this board.
#   * the source JSON used trailing commas and // comments; normalised to strict JSON.

FILESEXTRAPATHS:prepend:x570d4u := "${THISDIR}/${PN}:${THISDIR}/${PN}/${MACHINE}:"

PACKAGECONFIG:append:x570d4u = " json"

SRC_URI:append:x570d4u = " \
    file://fans.json \
    file://zones.json \
    file://events.json \
    file://groups.json \
    file://monitor.json \
    file://presence.json \
    "

do_configure:prepend:x570d4u() {
    install -d ${S}/control/config_files/${MACHINE}
    install -m 0644 ${UNPACKDIR}/fans.json   ${S}/control/config_files/${MACHINE}/
    install -m 0644 ${UNPACKDIR}/zones.json  ${S}/control/config_files/${MACHINE}/
    install -m 0644 ${UNPACKDIR}/events.json ${S}/control/config_files/${MACHINE}/
    install -m 0644 ${UNPACKDIR}/groups.json ${S}/control/config_files/${MACHINE}/

    install -d ${S}/monitor/config_files/${MACHINE}
    install -m 0644 ${UNPACKDIR}/monitor.json  ${S}/monitor/config_files/${MACHINE}/
    install -m 0644 ${UNPACKDIR}/presence.json ${S}/monitor/config_files/${MACHINE}/
}

# Ship the control loop masked.
#
# With empty fan headers fansensor never creates any /xyz/openbmc_project/control/fanpwm/*
# object, so phosphor-fan-control retries the lookup roughly every two seconds, forever.
# That is harmless in itself but writes ~43k journal lines a day into a RAM-backed journal
# capped at 8 MB, which evicts genuinely useful history -- it reached 24% of the journal
# within 14 minutes of boot on this system.
#
# The monitor and presence daemons are quiet and stay enabled. To turn control on once a
# fan is actually plugged into a motherboard header:
#
#     systemctl unmask phosphor-fan-control@0.service
#     systemctl start phosphor-fan-control@0.service
#
# Remove this block when the configuration has been validated against real fans.
do_install:append:x570d4u() {
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/phosphor-fan-control@0.service
}

FILES:${PN}:append:x570d4u = " ${sysconfdir}/systemd/system/phosphor-fan-control@0.service"
