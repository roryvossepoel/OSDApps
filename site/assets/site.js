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
