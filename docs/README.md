# ClawTV docs site

GitHub Pages source for clawtv.app docs.

## Pages

- `index.md` — landing
- `privacy.md` → `/privacy/` — App Store-required privacy policy
- `support.md` → `/support/` — App Store-required support page
- `appstore-listing.md` — internal copy for the App Store Connect listing (excluded from build)

## Enable GitHub Pages

Repo Settings → Pages → Source: `Deploy from a branch` → branch: `main` → folder: `/docs`. Build runs automatically on push.

Local preview:

```sh
cd docs
bundle install
bundle exec jekyll serve
```

## URL story

If a custom domain is configured (e.g. `clawtv.app`), the App Store Connect listing copy already references:

- Privacy policy URL: `https://clawtv.app/privacy/`
- Support URL: `https://clawtv.app/support/`

If sticking with the default GitHub Pages URL, replace those with `https://<user>.github.io/clawtv-public/privacy/` and `/support/` in the listing copy.
