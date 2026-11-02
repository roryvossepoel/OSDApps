"use strict";
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
