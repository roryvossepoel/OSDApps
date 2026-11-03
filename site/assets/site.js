"use strict";

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
