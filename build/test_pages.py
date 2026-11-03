from html.parser import HTMLParser
import json
from pathlib import Path
import unittest
from urllib.parse import urlsplit, unquote
from build_pages import ROOT, OUT, build

class Document(HTMLParser):
    def __init__(self, text):
        super().__init__(); self.ids=[]; self.links=[]; self.h1=0; self.main=0; self.current=0; self.lang=None
        self.feed(text)
    def handle_starttag(self, tag, attrs):
        a=dict(attrs)
        if 'id' in a: self.ids.append(a['id'])
        if tag=='html': self.lang=a.get('lang')
        if tag=='h1': self.h1+=1
        if tag=='main': self.main+=1
        if a.get('aria-current')=='page': self.current+=1
        for key in ('href','src'):
            if key in a: self.links.append(a[key])

class PagesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        build()
        cls.docs={p:Document(p.read_text()) for p in OUT.rglob('*.html')}
    def test_navigation_and_local_links_under_project_subpath(self):
        self.assertEqual(len(self.docs),7)
        for p,d in self.docs.items():
            with self.subTest(page=p.name):
                self.assertEqual(d.lang,'en');self.assertEqual(d.h1,1);self.assertEqual(d.main,1)
                self.assertEqual(d.current,0 if p.parent.name=='examples' else 1)
                self.assertEqual(len(d.ids),len(set(d.ids)))
                for link in d.links:
                    u=urlsplit(link)
                    if u.scheme:
                        self.assertIn(u.scheme,['https','http']);continue
                    self.assertFalse(link.startswith('/'),f'Root-relative URL breaks project Pages: {link}')
                    target=(p.parent/unquote(u.path)).resolve() if u.path else p
                    self.assertTrue(target.is_relative_to(OUT),link)
                    self.assertTrue(target.is_file(),f'{p.name}: {link}')
                    if u.fragment and target in self.docs:self.assertIn(unquote(u.fragment),self.docs[target].ids)
    def test_report_example_is_fictional_offline_and_linked(self):
        example=OUT/'examples/DeliveryReport.html'
        html=example.read_text()
        data=json.loads((OUT/'examples/DeliveryReport.json').read_text())
        self.assertIs(data['SampleData'],True)
        self.assertEqual(data['Device']['ComputerName'],'EXAMPLE-PC')
        self.assertIn('Fictional example',html)
        self.assertNotIn('<script',html)
        self.assertNotIn('<link',html)
        self.assertIn(data['ReportId'],html)
        self.assertIn('Built-in apps',html)
        self.assertIn('Repository apps',html)
        self.assertEqual(data['Counts']['Expected'],len(data['Packages']))
        self.assertEqual(data['WindowsUpdate']['InstalledCount'],len(data['WindowsUpdate']['Items']))
        for name in ['index.html','get-started.html','guides.html','faq.html','catalog/index.html']:
            self.assertIn('report.html', (OUT/name).read_text())

    def test_metadata_and_icons_are_bundled_from_current_revision(self):
        original=json.loads((ROOT/'metadata/builtins.json').read_text(encoding='utf-8-sig'))
        bundled=json.loads((OUT/'metadata/builtins.json').read_text())
        self.assertEqual(bundled['SchemaVersion'],2)
        self.assertEqual([x['Id'] for x in original['Packages']],[x['Id'] for x in bundled['Packages']])
        for item in bundled['Packages']:
            if item.get('IconUrl'):
                icon=OUT/'metadata'/item['IconUrl'];self.assertTrue(icon.is_file())
                self.assertEqual(icon.read_bytes(),(ROOT/'metadata/icons'/icon.name).read_bytes())
    def test_no_private_default_or_old_product_links(self):
        for p in OUT.rglob('*'):
            if p.suffix in ('.html','.js','.css','.json'):
                s=p.read_text()
                self.assertNotIn('msintune.blob.core.windows.net',s,str(p))
                self.assertNotIn('roryvossepoel/OSDApps',s,str(p))
                self.assertNotIn('571e6899e2596d6c59d54b8e2447223dba25481d',s,str(p))
        self.assertTrue((OUT/'.nojekyll').exists())
    def test_github_reference_paths_exist(self):
        prefix='https://github.com/roryvossepoel/OSDStage/blob/main/'
        for d in self.docs.values():
            for link in d.links:
                if link.startswith(prefix):self.assertTrue((ROOT/unquote(urlsplit(link[len(prefix):]).path)).is_file(),link)

if __name__=='__main__':unittest.main()
