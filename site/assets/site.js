"use strict";

// Theme preference: system by default, with optional light/dark override.
const themeMedia = window.matchMedia('(prefers-color-scheme: dark)');
const themeModes = ['system', 'light', 'dark'];
const readThemePreference = () => {
  try {
    const saved = localStorage.getItem('osdstage.theme');
    return themeModes.includes(saved) ? saved : 'system';
  } catch { return 'system'; }
};
let themePreference = readThemePreference();
const applyTheme = mode => {
  themePreference = themeModes.includes(mode) ? mode : 'system';
  if (themePreference === 'system') document.documentElement.removeAttribute('data-theme');
  else document.documentElement.setAttribute('data-theme', themePreference);
  document.documentElement.style.colorScheme = themePreference === 'system' ? 'light dark' : themePreference;
  try { localStorage.setItem('osdstage.theme', themePreference); } catch {}
};
applyTheme(themePreference);


// Keep the links visible without JavaScript; enhance the shared header only
// after the toggle and panel are both available.
const siteHeader = document.querySelector('.site-header');
const navToggle = siteHeader?.querySelector('.nav-toggle');
const navPanel = siteHeader?.querySelector('.nav-panel');
if (navToggle && navPanel) {
  const mobileNavigation = window.matchMedia('(max-width: 850px)');
  const setNavigationOpen = open => {
    const expanded = mobileNavigation.matches && open;
    navToggle.setAttribute('aria-expanded', String(expanded));
    navToggle.setAttribute('aria-label', expanded ? 'Close menu' : 'Open menu');
    navPanel.hidden = mobileNavigation.matches && !expanded;
  };
  const closeNavigation = (restoreFocus = false) => {
    setNavigationOpen(false);
    if (restoreFocus) navToggle.focus({preventScroll: true});
  };
  const syncNavigation = () => {
    const focused = document.activeElement;
    navToggle.hidden = !mobileNavigation.matches;
    setNavigationOpen(false);
    if (mobileNavigation.matches && navPanel.contains(focused)) {
      navToggle.focus({preventScroll: true});
    } else if (!mobileNavigation.matches && focused === navToggle) {
      navPanel.querySelector('a')?.focus({preventScroll: true});
    }
  };

  navToggle.addEventListener('click', () => {
    setNavigationOpen(navToggle.getAttribute('aria-expanded') !== 'true');
  });
  navPanel.addEventListener('click', event => {
    if (mobileNavigation.matches && event.target.closest('a')) {
      closeNavigation(navPanel.contains(document.activeElement));
    }
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && navToggle.getAttribute('aria-expanded') === 'true') {
      event.preventDefault();
      closeNavigation(true);
    }
  });
  document.addEventListener('click', event => {
    if (navToggle.getAttribute('aria-expanded') === 'true' && !siteHeader.contains(event.target)) {
      closeNavigation(navPanel.contains(document.activeElement));
    }
  });
  mobileNavigation.addEventListener('change', syncNavigation);
  syncNavigation();
}

document.querySelectorAll('.copy-code').forEach(button => {
  button.addEventListener('click', async () => {
    const code = button.closest('.code-block').querySelector('code');
    try {
      await navigator.clipboard.writeText(code.textContent);
      button.textContent = 'Copied';
    } catch {
      const selection = window.getSelection(), range = document.createRange();
      range.selectNodeContents(code); selection.removeAllRanges(); selection.addRange(range);
      button.textContent = 'Selected — copy manually';
    }
    setTimeout(() => { button.textContent = 'Copy'; }, 2500);
  });
});
function openGuide() {
  let id; try { id = decodeURIComponent(location.hash.slice(1)); } catch { return; }
  const target = document.getElementById(id);
  if (target && target.matches('details')) { target.open = true; target.scrollIntoView({block:'start'}); }
}
window.addEventListener('hashchange', openGuide);
openGuide();

// Animate once as lower sections enter. Content stays visible without JS,
// without IntersectionObserver, and when reduced motion is requested.
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
if (!reducedMotion.matches && 'IntersectionObserver' in window) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('scroll-revealed');
        observer.unobserve(entry.target);
      }
    });
  }, {threshold: 0.08});
  document.querySelectorAll('.home-section, .flow-strip, .home-bottom, .instruction, .next-step, .site-footer').forEach(section => {
    if (section.getBoundingClientRect().top >= window.innerHeight) observer.observe(section);
  });
}


// Shared header utilities: add a compact Share + GitHub control without
// duplicating menu markup across every page.
const existingGithubLink = siteHeader?.querySelector('.github-link');
if (existingGithubLink && !siteHeader.querySelector('.header-actions')) {
  const actions = document.createElement('div');
  actions.className = 'header-actions';

  const shareButton = document.createElement('button');
  shareButton.type = 'button';
  shareButton.className = 'header-icon share-button';
  shareButton.setAttribute('aria-label', 'Share this page');
  shareButton.setAttribute('aria-haspopup', 'dialog');
  shareButton.setAttribute('aria-expanded', 'false');
  shareButton.title = 'Share this page';
  shareButton.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.7 10.7 6.6-4.1M8.7 13.3l6.6 4.1"/></svg><span class="sr-only">Share</span>';

  existingGithubLink.classList.add('header-icon');
  existingGithubLink.setAttribute('aria-label', 'OSDStage on GitHub');
  existingGithubLink.title = 'OSDStage on GitHub';
  existingGithubLink.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.8a9.4 9.4 0 0 0-3 18.3c.5.1.6-.2.6-.4v-1.8c-2.7.6-3.3-1.1-3.3-1.1-.4-1.1-1.1-1.4-1.1-1.4-.9-.6.1-.6.1-.6 1 0 1.5 1 1.5 1 .9 1.5 2.3 1.1 2.9.8.1-.6.4-1.1.7-1.3-2.2-.2-4.5-1.1-4.5-4.7 0-1 .4-1.9 1-2.5-.1-.3-.4-1.2.1-2.5 0 0 .8-.3 2.6 1a9.1 9.1 0 0 1 4.8 0c1.8-1.2 2.6-1 2.6-1 .5 1.3.2 2.2.1 2.5.6.6 1 1.5 1 2.5 0 3.6-2.3 4.5-4.5 4.7.4.3.7.9.7 1.7v2.6c0 .3.2.5.7.4A9.4 9.4 0 0 0 12 2.8Z"/></svg><span class="sr-only">GitHub</span>';

  const popover = document.createElement('div');
  popover.className = 'share-popover';
  popover.hidden = true;
  popover.setAttribute('role', 'dialog');
  popover.setAttribute('aria-label', 'Share OSDStage');
  popover.innerHTML = `
    <h2>Share OSDStage</h2>
    <p>Share this page with someone else.</p>
    <div class="share-options">
      <button class="share-option" type="button" data-share="copy"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 13a5 5 0 0 0 7.1 0l2-2a5 5 0 0 0-7.1-7.1l-1.1 1.1"/><path d="M14 11a5 5 0 0 0-7.1 0l-2 2A5 5 0 0 0 12 20.1l1.1-1.1"/></svg><span>Copy link</span></button>
      <button class="share-option" type="button" data-share="native"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.7 10.7 6.6-4.1M8.7 13.3l6.6 4.1"/></svg><span>Share…</span></button>
      <div class="share-separator" aria-hidden="true"></div>
      <a class="share-option" data-share-link="x"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4l14 16M19 4 5 20"/></svg><span>X</span></a>
      <a class="share-option" data-share-link="bluesky"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 11c-1.1-2.1-4-5.5-6.7-7.4C2.7 1.8 1.7 2.1 1 2.4.2 2.8 0 4 0 4.7c0 .8.4 6.4.7 7.3 1 3.3 4.4 4.4 7.4 3.9-5.2.9-6.6 4.1-3.7 7.3 5.4 5.6 7.6-1.2 7.6-4.7 0 3.5 2.2 10.3 7.6 4.7 2.9-3.2 1.5-6.4-3.7-7.3 3 .5 6.4-.6 7.4-3.9.3-.9.7-6.5.7-7.3 0-.7-.2-1.9-1-2.3-.7-.3-1.7-.6-4.3 1.2C16 5.5 13.1 8.9 12 11Z"/></svg><span>Bluesky</span></a>
      <a class="share-option" data-share-link="linkedin"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="9" width="4" height="12"/><path d="M5 3.5v.01M11 21V9h4v2c.9-1.4 2.2-2.3 4-2.3 2.8 0 4 1.8 4 5.1V21h-4v-6.3c0-1.5-.5-2.5-1.9-2.5-1.6 0-2.1 1.1-2.1 3V21Z"/></svg><span>LinkedIn</span></a>
      <a class="share-option" data-share-link="email"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m4 7 8 6 8-6"/></svg><span>Email</span></a>
    </div>`;

  existingGithubLink.parentNode.insertBefore(actions, existingGithubLink);
  actions.append(shareButton, existingGithubLink, popover);

  const currentUrl = location.href;
  const currentTitle = document.title.replace(/ · OSDStage$/, '') || 'OSDStage';
  const shareText = `${currentTitle} · OSDStage`;
  const encodedUrl = encodeURIComponent(currentUrl);
  const encodedText = encodeURIComponent(`${shareText} ${currentUrl}`);

  const directLinks = {
    x: `https://x.com/intent/tweet?text=${encodedText}`,
    bluesky: `https://bsky.app/intent/compose?text=${encodedText}`,
    linkedin: `https://www.linkedin.com/sharing/share-offsite/?url=${encodedUrl}`,
    email: `mailto:?subject=${encodeURIComponent(shareText)}&body=${encodeURIComponent(currentUrl)}`
  };
  popover.querySelectorAll('[data-share-link]').forEach(link => {
    link.href = directLinks[link.dataset.shareLink];
    if (link.dataset.shareLink !== 'email') {
      link.target = '_blank';
      link.rel = 'noreferrer';
    }
  });

  const nativeButton = popover.querySelector('[data-share="native"]');
  if (!navigator.share) nativeButton.hidden = true;

  const setShareOpen = open => {
    shareButton.setAttribute('aria-expanded', String(open));
    popover.hidden = !open;
  };
  shareButton.addEventListener('click', () => setShareOpen(popover.hidden));
  popover.querySelector('[data-share="copy"]').addEventListener('click', async event => {
    const label = event.currentTarget.querySelector('span');
    try {
      await navigator.clipboard.writeText(currentUrl);
      label.textContent = 'Link copied';
    } catch {
      const input = document.createElement('input');
      input.value = currentUrl;
      document.body.append(input);
      input.select();
      document.execCommand('copy');
      input.remove();
      label.textContent = 'Link copied';
    }
    setTimeout(() => { label.textContent = 'Copy link'; }, 1800);
  });
  nativeButton.addEventListener('click', async () => {
    try { await navigator.share({title: shareText, url: currentUrl}); } catch {}
  });
  document.addEventListener('click', event => {
    if (!actions.contains(event.target)) setShareOpen(false);
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && !popover.hidden) {
      setShareOpen(false);
      shareButton.focus({preventScroll: true});
    }
  });
}



// Keep appearance controls out of the primary header. The footer offers
// explicit System / Light / Dark choices and reflects the saved preference.
const siteFooter = document.querySelector('.site-footer');
if (siteFooter && !siteFooter.querySelector('.footer-theme')) {
  const themeControl = document.createElement('div');
  themeControl.className = 'footer-theme';
  themeControl.setAttribute('role', 'group');
  themeControl.setAttribute('aria-label', 'Appearance');
  themeControl.innerHTML = `
    <span class="footer-theme-label">Appearance</span>
    <div class="footer-theme-options">
      <button type="button" data-theme-mode="system">System</button>
      <button type="button" data-theme-mode="light">Light</button>
      <button type="button" data-theme-mode="dark">Dark</button>
    </div>`;

  const syncFooterTheme = () => {
    themeControl.querySelectorAll('[data-theme-mode]').forEach(button => {
      const selected = button.dataset.themeMode === themePreference;
      button.setAttribute('aria-pressed', String(selected));
    });
  };

  themeControl.addEventListener('click', event => {
    const button = event.target.closest('[data-theme-mode]');
    if (!button) return;
    applyTheme(button.dataset.themeMode);
    syncFooterTheme();
  });

  themeMedia.addEventListener('change', () => {
    if (themePreference === 'system') applyTheme('system');
  });

  syncFooterTheme();
  siteFooter.append(themeControl);
}

// Small dependency-free PowerShell highlighter for the site's short examples.
function highlightPowerShell(code) {
  if (code.dataset.highlighted === 'true') return;
  const source = code.textContent;
  const tokenPattern = /(#.*$)|('(?:''|[^'])*'|"(?:`.|[^"])*")|(\$[A-Za-z_][\w:]*)|(\b(?:Add|Get|Set|Test|Sync|Install|Import|Format|Convert|Start|Remove|Join|Where|Select|New)-[A-Za-z0-9-]+\b)|(-[A-Za-z][A-Za-z0-9-]*)|(\b(?:True|False|null)\b)|([|`])/gmi;
  let last = 0;
  const fragment = document.createDocumentFragment();
  for (const match of source.matchAll(tokenPattern)) {
    if (match.index > last) fragment.append(document.createTextNode(source.slice(last, match.index)));
    const span = document.createElement('span');
    span.className = match[1] ? 'ps-comment' :
      match[2] ? 'ps-string' :
      match[3] ? 'ps-variable' :
      match[4] ? 'ps-cmdlet' :
      match[5] ? 'ps-param' :
      match[6] ? 'ps-keyword' : 'ps-operator';
    span.textContent = match[0];
    fragment.append(span);
    last = match.index + match[0].length;
  }
  if (last < source.length) fragment.append(document.createTextNode(source.slice(last)));
  code.replaceChildren(fragment);
  code.dataset.highlighted = 'true';
}
document.querySelectorAll('.code-block pre code, .preview-code pre code').forEach(highlightPowerShell);
