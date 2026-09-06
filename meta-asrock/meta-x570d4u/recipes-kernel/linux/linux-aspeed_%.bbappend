FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:x570d4u = " \
    file://x570d4u.cfg \
    file://0001-x570d4u-enable-unused-fan-tach-channels.patch \
"
