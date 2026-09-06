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

    # Attribution badge: GitHub mark plus the author, the whole thing a link.
    # Injected after the Vue mount point rather than into a component, so it
    # survives route changes and needs no webui-vue patch. The mark is inline
    # SVG so nothing is fetched from an external host.
    sed -i 's|<div id="app"></div>|<div id="app"></div>\n    <a id="x570d4u-credit" href="https://github.com/Gucioo/openbmc" target="_blank" rel="noopener noreferrer" title="ASRock Rack X570D4U-2L2T OpenBMC mod by Gucioo"><svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true" focusable="false"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.012 8.012 0 0 0 16 8c0-4.42-3.58-8-8-8z"/></svg><span>Gucioo</span></a>|' \
        ${D}${datadir}/www/index.html

    grep -q 'x570d4u-credit' ${D}${datadir}/www/index.html || \
        bbfatal "credit badge: failed to inject the link into index.html"
}
