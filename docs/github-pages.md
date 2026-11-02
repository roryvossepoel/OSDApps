# GitHub Pages

[Documentation](README.md) · [Viewers](viewer.md)

The static website lives in `site/`. It contains Home, Get started, Catalog,
Guides and FAQ. Detailed module reference remains in this repository.

## Proposed documentation direction

Use GitHub Pages as the primary user-facing home: Get started, task guides,
copyable examples, package authoring, results/troubleshooting and FAQ. Keep the
home page short; put detail on dedicated pages with clear navigation. Users
should be able to complete normal deployment tasks without opening GitHub files.

The repository remains the source of truth for documentation, command help,
technical contracts, development and test evidence. Before expanding the site,
add a build step that renders the user guides from their canonical source files.
Do not hand-maintain the same instructions in both Markdown and HTML. Keep a
visible release/version context so unreleased commands are not presented as
available in the Gallery release.

This is the proposed next structure, not a completed content migration. The
current static site still links to repository guides for detailed reference.
The [source register](sources.md) is available from the website footer now.

## Review and publish

1. Open the website pull request and wait for **GitHub Pages / Build and check website** and the normal module CI checks.
2. Download the **OSDStage-Website** artifact to review the generated files with a local HTTP server.
3. In repository **Settings → Pages → Build and deployment**, select **GitHub Actions** as the source.
4. Merge the reviewed pull request. The main-branch website workflow builds and publishes through the `github-pages` environment.
5. Open the URL reported by **Publish website**. Repository/environment protection rules still apply.

Pull requests build an artifact; they do not publish. A manual **GitHub Pages**
workflow run on `main` can rebuild the site after enabling Pages. Changes to
website sources, the builder or bundled metadata also trigger publication.
This workflow does not publish the PowerShell module to the Gallery.

## Build and check locally

From the repository root, with Python 3.9+ and Node.js installed:

```sh
python3 build/build_pages.py
python3 -m unittest discover -s build -p test_pages.py -v
node build/test_catalog.cjs
node --check site/assets/site.js
node --check site/catalog/app.js
python3 -m http.server 8000 --directory dist/site
```

Open `http://localhost:8000/`. Use an HTTP server rather than opening HTML through
`file://`: the catalog fetches JSON. The generated output is `dist/site` and is
not committed. The builder copies the current `metadata/builtins.json` and its
icons into the site, and rewrites icon URLs to those local assets.

The Python checks cover markup, relative links/anchors, documentation links and
bundled metadata/icons. The Node checks cover catalog loading, filtering,
pagination, display preferences, failure retention and schema/URL validation.
`Tests/WebsiteExamples.Tests.ps1`, run by normal module CI, parses the PowerShell
examples and checks public command names and parameters without executing them.
Browser review should also cover navigation, copying, guide expansion and narrow
screens after layout changes.

## Catalog behavior

Built-ins load from the bundled metadata. There is no default organization URL
and no demo catalog. Users can enter their own schema 2 catalog URL, or explicitly
open `catalog/index.html?catalog=<URL-encoded HTTPS catalog URL>`.

The browser fetches the catalog and referenced manifests directly. Their host
must permit browser requests through CORS, including the deployed Pages origin.
Use HTTPS for catalogs and manifests on the HTTPS site. The viewer does not use a
proxy, authentication backend or package installer. It does not download ZIP
payloads or inspect the local target/cache. Do not put credentials in shared URLs.
Only display preferences are saved locally; the entered repository URL is not
stored by the viewer.

## Content maintenance

- Keep the home page short. Put task examples in the expandable guides and link to full reference for details.
- Keep every command example explicit about preparation Windows, target WinPE or the installed target.
- The quick start uses only the online Gallery route with `-AllowPrerelease`. Keep the publication-pending notice until the RC upload and exact-content verification succeed. Remove `-AllowPrerelease` when documenting a verified GA release.
- Keep links relative so the site works under the repository project path and on a custom domain.
- No external fonts, analytics, framework build or backend is required.

[Back to documentation](README.md)
