# Fan control for the motherboard fan headers.
#
# The control path is verified on real hardware: the curve computes a target, phosphor-fan
# writes it over xyz.openbmc_project.Control.FanPwm, and dbus-sensors lands it in the
# aspeed_pwm_tacho pwm1..pwm6 registers. What is NOT verified is behaviour with a fan
# actually spinning -- nothing is connected to the headers on this system, so the tach
# feedback path (monitor/presence, fault detection, the "deviation" tolerance) has never
# run against a real fan.
#
# The PWM outputs exist regardless of whether a fan is plugged in, because they come from
# the entity-manager IntelFanConnector exposes (see x570d4u.json), not from fan detection.
# Without those connectors dbus-sensors creates no /xyz/openbmc_project/control/fanpwm/*
# object at all and phosphor-fan-control retries the lookup every two seconds forever.
#
# Adapted from Renze Nicolai's X570D4U port (github.com/renzenicolai/openbmc-x570d4u).
# Changes needed for this system:
#   * inventory paths rebased from .../system/chassis/x570d4u/... onto this board's
#     entity-manager path, .../system/board/ASRock_Rack_X570D4U_2L2T/... -- in groups.json
#     and also in monitor.json and presence.json, which the original port left behind.
#   * events.json referenced four groups that groups.json never defined (zone0_ocp,
#     zone0_bp_nvme, zone0_m2_nvme) plus fan7/fan8, so those curves were dead. Meanwhile
#     zone0_cpu was defined but unused, meaning CPU temperature drove nothing at all.
#     Rewritten around the two temperatures this board actually publishes: MB_Temp and
#     CPU_Temp, both from the W83773G and both verified correct.
#   * dropped the fan-not-present and fan-not-functional events, which forced the zone to
#     255 whenever any one of the six fans was missing. On this board the headers are
#     optionally populated, so a single connected fan would have been pinned at 100%
#     because the other five headers are empty.
#   * zones.json had default_floor 255, i.e. a 100% floor. Now 77 (30%), matching the PSU
#     fan floor, with poweron_target 128 (50%).
#   * the source JSON used trailing commas and // comments; normalised to strict JSON.
#
# Targets throughout are raw PWM 0-255 (dbus-sensors PwmSensor targetIfaceMax = 255).

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

