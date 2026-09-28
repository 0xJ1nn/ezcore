"""Verify canonical final build, all 36 platform/screens and live behavior.

Capture must be deterministic: the committed PNGs are release evidence, so the
same source has to produce the same pixels. Two settings enforce that.

- ``reduced_motion='reduce'`` makes the prototype's own
  ``@media(prefers-reduced-motion:reduce)`` rule apply, which sets
  ``animation:none!important`` on every element. Without it, the overlay
  screenshots race its ``.3s`` fade-in.
- ``LAUNCH_ARGS`` pins colour profile, text antialiasing and rasterization so
  the compositor does not vary with the host GPU.

``settle()`` is the belt-and-braces check: it waits for every animation and
transition in both frames to finish before a screenshot is taken.

Every capture also passes ``animations='disabled'``: Playwright fast-forwards
finite CSS transitions and animations to their end state at the moment of the
screenshot. ``settle()`` cannot see a transition that *starts after it ran*
(rAF-throttled reflow can begin one tick late), and a capture taken inside
that tail recorded a sub-pixel offset of the re-centering cover flow — two
symmetric ~9-pixel antialiasing clusters at the selected cover's edges,
flipping ``responsive-768.png`` between two byte states across runs.
Fast-forwarding at capture time closes that window. See issue #35.
"""
from pathlib import Path
import json
import struct
from playwright.sync_api import sync_playwright
ROOT = Path(__file__).parent
OUT = ROOT / 'verification'
OUT.mkdir(exist_ok=True)


def png_size(path):
    """Pixel size of a PNG, read from the IHDR chunk. Stdlib only, so this
    script keeps working without Pillow."""
    with open(path, 'rb') as handle:
        head = handle.read(24)
    if head[:8] != b'\x89PNG\r\n\x1a\n' or head[12:16] != b'IHDR':
        raise AssertionError(f'{path} is not a PNG')
    return struct.unpack('>II', head[16:24])

LAUNCH_ARGS = [
    '--force-color-profile=srgb',
    '--disable-lcd-text',
    '--font-render-hinting=none',
    '--disable-partial-raster',
    '--disable-skia-runtime-opts',
    # NOT --deterministic-mode: it stops the compositor producing frames, so
    # Playwright's actionability check never sees an element become *stable*
    # and every click() blocks until timeout. Verified by bisecting this list
    # one flag at a time: the other seven are fine, this one hangs the run.
    # See issue #35.
    '--run-all-compositor-stages-before-draw',
    '--disable-new-content-rendering-timeout',
]

SETTLE_JS = """() => Promise.all(
    [document, ...Array.from(document.querySelectorAll('iframe'))]
      .flatMap(d => { try { return [d]; } catch (e) { return []; } })
      .flatMap(d => (d.getAnimations ? d.getAnimations() : []))
      .map(a => a.finished.catch(() => {}))
)"""

# The toast is a transient notification that self-hides on a 3000ms timer
# (`setTimeout(() => ... classList.remove('show'), 3000)` in the prototype).
# getAnimations() cannot see that: a JS timer is not a CSS animation, so
# SETTLE_JS returns immediately while the toast is still on screen. Whether a
# capture caught it mid-life then depends on how long the preceding steps took,
# which is exactly the kind of timing-dependent evidence this PR exists to
# eliminate -- it was the sole remaining source of pixel drift, worth ~2% of
# settings-emulation.png. Dismissing any visible toast before capture makes the
# evidence independent of how fast the machine ran.
HIDE_TRANSIENT_JS = """() => {
  for (const frame of [document, ...Array.from(document.querySelectorAll('iframe'))]) {
    let doc;
    try { doc = frame.contentDocument || frame; } catch (e) { continue; }
    if (!doc || !doc.querySelector) continue;
    for (const el of doc.querySelectorAll('.toast.show')) el.classList.remove('show');
  }
}"""

# The overlay is 79% opaque (background:#02070dc9) and relies on
# backdrop-filter:blur(24px) to make the 21% show-through unreadable. If the
# fade-in is captured mid-flight, or the backdrop filter is not composited, the
# library behind it stays legible and the evidence looks broken. Assert the
# mechanism, not the appearance, so the check survives theme changes.
OVERLAY_BACKDROP_JS = """() => {
  const o = document.querySelector('#overlay');
  if (!o) return null;
  const cs = getComputedStyle(o);
  const d = o.querySelector('.dialog');
  const ds = d ? getComputedStyle(d) : null;
  return {
    backdropFilter: cs.backdropFilter || cs.webkitBackdropFilter || 'none',
    // The alpha is the last number in "rgba(r, g, b, a)". The group is
    // required: /[\\d.]+\\)$/ without it also consumes the ")" and returns
    // "0.79)", which float() rejects. See issue #35.
    overlayAlpha: (cs.backgroundColor.match(/([\\d.]+)\\)$/) || [null, '1'])[1],
    dialogBackground: ds ? ds.backgroundColor : null,
    dialogHasImage: !!(ds && ds.backgroundImage && ds.backgroundImage !== 'none'),
  };
}"""

report = {'build':'ezcore-final-01','matrix':[],'checks':[],'errors':[]}

# The prototype's shell header renders a live clock: new Date().toLocaleTimeString()
# refreshed on a 30s interval (ezCORE-Orbit.html:996). Two runs a minute apart
# therefore captured different digits, which is why 32 of the 57 PNGs differed
# in real pixels even with every launch flag pinned. No browser flag can freeze
# a page's own Date; freezing the clock before any script runs is the only way
# to make the evidence reproducible. Fixed instant, chosen to be an arbitrary
# round value so nobody mistakes it for a real observation.
FROZEN_INSTANT = '2026-01-01T09:41:00'

with sync_playwright() as p:
    browser = p.chromium.launch(args=LAUNCH_ARGS)
    context = browser.new_context(
        viewport={'width':1440,'height':1100},
        device_scale_factor=1,
        reduced_motion='reduce',
    )
    page = context.new_page()
    # Install on the CONTEXT, not the page: the clock widget lives inside the
    # prototype iframe, and page.clock only covers the wrapper frame. That is
    # why a page-scoped install still left the minutes ticking in the captures.
    context.clock.install(time=FROZEN_INSTANT)
    page.on('pageerror',lambda e: report['errors'].append(str(e)))
    page.goto('http://127.0.0.1:8770/',wait_until='networkidle')
    page.reload(wait_until='networkidle')
    assert page.locator('body').get_attribute('data-brand-build') == report['build']
    page.wait_for_function('typeof frame?.contentWindow?.orbitNavigate === "function"')
    for platform in ['ios','android','mac','windows','linux','web']:
        page.locator(f'#tab-{platform}').click()
        page.wait_for_function('ready && frame.contentWindow.document.body.dataset.brandBuild === "ezcore-final-01"')
        child = page.frames[1]
        for screen in ['library','systems','details','vault','pause','settings']:
            page.locator(f'[data-screen="{screen}"]').click()
            selector = '#overlay .dialog' if screen in ['details','pause'] else '#'+screen
            child.locator(selector).wait_for(state='visible')
            child.wait_for_function('Array.from(document.images).filter(x=>x.getClientRects().length).every(x=>x.complete && x.naturalWidth>0)')
            child.evaluate(HIDE_TRANSIENT_JS)
            child.evaluate(SETTLE_JS)
            if screen in ('details','pause'):
                backdrop = child.evaluate(OVERLAY_BACKDROP_JS)
                assert backdrop is not None, (platform, screen, 'overlay missing')
                assert backdrop['backdropFilter'] != 'none', (
                    'overlay lost backdrop-filter; the 21% show-through would stay '
                    'legible and the screenshot would capture a broken overlay',
                    platform, screen, backdrop)
                assert float(backdrop['overlayAlpha']) >= 0.7, (
                    'overlay background too transparent to obscure content without a '
                    'working backdrop filter', platform, screen, backdrop)
                assert backdrop['dialogHasImage'] or backdrop['dialogBackground'], (
                    'dialog has no opaque surface of its own', platform, screen, backdrop)
            measurements = child.evaluate('''() => ({width:innerWidth,height:innerHeight,scrollWidth:document.documentElement.scrollWidth,scrollHeight:document.documentElement.scrollHeight,accent:getComputedStyle(document.documentElement).getPropertyValue('--accent').trim(),visibleText:document.body.innerText.length})''')
            assert measurements['scrollWidth'] <= measurements['width'], (platform, screen, measurements)
            assert measurements['accent'].lower() == '#007bff', measurements
            assert measurements['visibleText'] > 100
            if screen == 'library':
                child.evaluate(HIDE_TRANSIENT_JS)
                child.evaluate(SETTLE_JS)
                box = child.evaluate('''() => {const a=document.querySelector('.game-case.selected').getBoundingClientRect(),b=document.querySelector('.flow').getBoundingClientRect();return {top:a.top-b.top,bottom:b.bottom-a.bottom}}''')
                assert box['top'] >= -1 and box['bottom'] >= -1, (platform,box)
            shot = OUT/f'{platform}-{screen}.png'
            child.evaluate(HIDE_TRANSIENT_JS)
            child.evaluate(SETTLE_JS)
            page.screenshot(path=str(shot),full_page=True,animations='disabled')
            # Record the size of the FILE that was just written, not the child
            # frame's viewport. The screenshot is full_page and covers the whole
            # wrapper (masthead + device shell + footer), so its pixel size is
            # deliberately different from innerWidth/innerHeight. The evidence
            # gate cross-checks the report against the PNG headers, so recording
            # the viewport here would make that check impossible to satisfy.
            report['matrix'].append({
                'platform':platform,'screen':screen,
                'viewportWidth':measurements['width'],'viewportHeight':measurements['height'],
                'captureWidth':png_size(shot)[0],'captureHeight':png_size(shot)[1],
                'scrollWidth':measurements['scrollWidth'],
                'scrollHeight':measurements['scrollHeight'],
                'accent':measurements['accent'],
                'visibleText':measurements['visibleText'],
            })
    report['checks'].append('36 platform/screen states; decoded visible images; no horizontal overflow; selected cover inside stage; final blue tokens; height and scrollHeight recorded per state')
    report['checks'].append('Overlay keeps a working backdrop-filter and an opaque enough scrim on all 12 details/pause states')
    page.locator('[data-screen="library"]').click()
    child = page.frames[1]
    before=child.locator('#selection h2').inner_text()
    child.locator('.next').click()
    assert child.locator('#selection h2').inner_text()!=before
    child.locator('[data-filter="GBA"]').click()
    assert child.locator('.game-case').count()==2
    child.locator('#grid-view').click()
    assert child.locator('#game-grid').is_visible()
    child.locator('#search').fill('not-a-title')
    assert child.locator('#no-games').is_visible()
    child.locator('#clear-filters').click()
    child.locator('#flow-view').click()
    child.locator('#details-selected').click()
    child.locator('#favorite').click()
    assert child.locator('#favorite').get_attribute('aria-pressed')=='true'
    child.locator('.close').press('Escape')
    assert child.locator('#overlay').is_hidden()
    child.locator('#play-selected').click()
    child.locator('#save-demo').click()
    child.locator('#open-capsule').click()
    assert child.locator('#vault-grid .save-card').count()==4
    report['checks'].append('Cover navigation, system filter, grid, search empty/reset, favorite, Escape, demo save and capsule')
    page.locator('[data-screen="settings"]').click()
    for setting in ['Appearance','Emulation','Controllers','Audio','Library & storage','About ezCORE']:
        child.locator(f'[data-setting="{setting}"]').click()
        assert child.locator('#settings-panel h2').is_visible()
        child.evaluate(HIDE_TRANSIENT_JS)
        child.evaluate(SETTLE_JS)
        page.screenshot(path=str(OUT/('settings-'+setting.split()[0].lower()+'.png')),full_page=True,animations='disabled')
    child.locator('[data-setting="Appearance"]').click()
    child.locator('[data-toggle="motion"]').click()
    assert child.locator('[data-toggle="motion"]').get_attribute('aria-checked')=='false'
    page.reload(wait_until='networkidle')
    page.wait_for_function('ready && typeof frame.contentWindow.orbitNavigate === "function"')
    child=page.frames[1]
    assert child.locator('body').evaluate('(x)=>x.classList.contains("still")')
    report['checks'].append('All six settings tabs and local preference persistence')
    page.locator('#tab-mac').click()
    page.wait_for_function('ready')
    page.locator('[data-window="minimize"]').click()
    assert page.locator('#restore-card').is_visible()
    page.locator('#restore-button').click()
    assert page.locator('#shell-host').is_visible()
    page.locator('[data-window="maximize"]').click()
    assert page.locator('#stage').evaluate('(x)=>x.classList.contains("expanded")')
    page.locator('#expanded-exit').click()
    page.locator('#shell-button').click()
    assert page.locator('#stage').evaluate('(x)=>x.classList.contains("flat")')
    page.locator('#shell-button').click()
    page.locator('#brand-guide-button').click()
    assert page.locator('#brand-guide').is_visible()
    page.evaluate(HIDE_TRANSIENT_JS)
    page.evaluate(SETTLE_JS)
    page.screenshot(path=str(OUT/'brand-identity.png'),full_page=True,animations='disabled')
    page.keyboard.press('Escape')
    assert not page.locator('#brand-guide').is_visible()
    report['checks'].append('Minimize/restore, maximize/exit focus, shell mode and brand guide dialog')
    for width in [390,768]:
        page.set_viewport_size({'width':width,'height':900})
        page.locator('#tab-ios').click()
        page.wait_for_function('ready')
        assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
        child=page.frames[1]
        child.evaluate(HIDE_TRANSIENT_JS)
        child.evaluate(SETTLE_JS)
        page.screenshot(path=str(OUT/f'responsive-{width}.png'),full_page=True,animations='disabled')
    report['checks'].append('390px and 768px responsive wrapper without horizontal overflow')
    # Legacy prefs retain user collections and migrate the old lime accent.
    page.set_viewport_size({'width':1440,'height':1100})
    page.evaluate('localStorage.setItem("orbit-prefs",JSON.stringify({accent:"#c5f477",motion:false}))')
    page.reload(wait_until='networkidle')
    page.wait_for_function('ready')
    assert page.frames[1].evaluate('getComputedStyle(document.documentElement).getPropertyValue("--accent").trim()')=='#007bff'
    report['checks'].append('Legacy lime preference cannot override finalized blue identity')
    assert not report['errors'], report['errors']
    browser.close()
(OUT/'report.json').write_text(json.dumps(report,indent=2))
print(json.dumps({'build':report['build'],'matrix_states':len(report['matrix']),'checks':report['checks'],'errors':report['errors'],'evidence':str(OUT)},indent=2))
