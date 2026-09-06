# Dark theme.
#
# Bootstrap 5.3's dark theme is already compiled into webui-vue's CSS -- it only needs
# data-bs-theme="dark" on <html>. That alone leaves the main content light, because
# webui-vue hardcodes light colours in ~28 component rules (form controls, tables,
# .nav-container, .card .bg-* tints) and forces color:#161616!important on every label,
# which renders label text invisible on a dark surface. dark-overrides.css restyles those
# using Bootstrap's own dark scale.
#
# Selectors deliberately avoid Vue scoped-style hashes (e.g. [data-v-87dd92f4]) because
# those change on every webui-vue rebuild.

FILESEXTRAPATHS:prepend:x570d4u := "${THISDIR}/${PN}:"

SRC_URI:append:x570d4u = " file://dark-overrides.css"

do_install:append:x570d4u() {
    install -m 0644 ${UNPACKDIR}/dark-overrides.css ${D}${datadir}/www/css/dark-overrides.css

    sed -i 's|<html lang="en">|<html lang="en" data-bs-theme="dark">|' \
        ${D}${datadir}/www/index.html
    sed -i 's|\(<link rel="stylesheet" crossorigin href="/css/app[^"]*\.css">\)|\1\n    <link rel="stylesheet" href="/css/dark-overrides.css">|' \
        ${D}${datadir}/www/index.html

    grep -q 'data-bs-theme="dark"' ${D}${datadir}/www/index.html || \
        bbfatal "dark theme: failed to patch <html> in index.html"
    grep -q 'dark-overrides.css' ${D}${datadir}/www/index.html || \
        bbfatal "dark theme: failed to inject the stylesheet link into index.html"
}
