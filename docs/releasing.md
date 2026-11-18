# Releasing

The repository, the npm package, and the git tag carry the same version. Users
pick up changes in one of two ways: `npx` resolves the npm version, and an
installed machine refreshes by re-running the installer.

## What a version means

| Surface | Source of truth |
|---|---|
| `npm` package | `package.json` `version`, published tarball |
| git tag | `v<version>`, created from the release commit |
| installed harness | re-run by the installer from the repository |

Keep them equal. `npx herdr-agent-team@0.2.0`, tag `v0.2.0`, and `package.json`
`0.2.0` are the same release.

## Steps

1. **Land the change on `main`** and let the suites pass:

   ```bash
   skills/herdr-agent-team/harness/tests/validate.sh
   docs/check.sh
   ```

2. **Choose the bump.**
   - `patch` — fixes, docs, wording.
   - `minor` — a new command or a new behaviour.
   - `major` — a changed file layout, environment variable, or protocol contract.

3. **Bump, commit, and tag in one step:**

   ```bash
   npm version patch --message "chore(release): v%s"
   git push origin main --follow-tags
   ```

   `npm version` refuses a dirty tree on purpose: the tarball is built from the
   working directory, not from git.

4. **Publish.**

   If the account requires proof-of-presence (staged publishing):

   ```bash
   npm stage publish .
   npm stage list
   npm stage approve <stage-id>     # asks for 2FA, this is the human step
   ```

   Otherwise:

   ```bash
   npm publish --access public
   ```

   A brand-new package name first gains a `0.0.0-stage` placeholder. It is
   npm's, it is harmless, and it stops being `latest` once a real version lands.

5. **Verify before announcing:**

   ```bash
   npm view herdr-agent-team version
   npm dist-tag ls herdr-agent-team
   npx -y herdr-agent-team@<version> --dry-run
   ```

6. **Update the docs only if they name a version.** The README and the site use
   `@latest`, so a release rarely needs a documentation commit.

## How users update

| What they want | Command |
|---|---|
| the installer at the newest release | `npx -y herdr-agent-team@latest --yes` |
| a pinned installer | `npx -y herdr-agent-team@0.2.0 --yes` |
| refresh an installed machine | `npx -y herdr-agent-team@latest --yes` (re-runs the skill layer, the runtime, and the deep check) |
| refresh only the skill layer | `npx skills update herdr-agent-team -g -y` |

Nothing auto-updates. A machine keeps the version it installed until someone
runs the installer again, and `hteam health` reports what the machine actually
has.

## Rules

- **Never reuse a version.** npm keeps a unique version per package name.
- **Never force-push a release tag.** If a release is wrong, publish the next
  patch; moves that rewrite history are the Human's call.
- **Deprecate, do not unpublish.** `npm deprecate herdr-agent-team@0.2.0 "use 0.2.1"` keeps
  existing installs resolvable and warns at install time.
- **Prereleases need an explicit tag.** `0.3.0-beta.1` must be published with
  `--tag beta`; the default `latest` refuses non-latest semver. A staged
  version's tag is immutable, so reject and re-stage to change it.
- **A staged version shares the version index.** You cannot publish a version that
  is already staged; approve or reject it first.

## Later: trusted publishing

After the first successful release, configure a trusted publisher for
`tomozard/agent-skills` on the package's npm settings, then let CI release:

```yaml
permissions:
  contents: read
  id-token: write
steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-node@v4
    with: { node-version: 20, registry-url: https://registry.npmjs.org }
  - run: npm publish --provenance --access public
```

No OTP and no long-lived token. The repository does not ship this workflow yet;
add it only once the trusted publisher is configured.
