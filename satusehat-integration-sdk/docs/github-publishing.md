# Publishing to GitHub

## 1. Review identity/governance

Before an official publication, replace/confirm:

- repository organization and URL;
- package registry namespaces;
- copyright/NOTICE owner;
- maintainer/security contact;
- official branding and repository description.

## 2. Initialize repository

```bash
git init
git branch -M main
git add .
git commit -m "feat: initial SATUSEHAT integration SDK reference implementation"
```

## 3. Create remote repository

Create an empty GitHub repository, then:

```bash
git remote add origin <official-github-repository-url>
git push -u origin main
```

## 4. Repository settings

Recommended:

- protect `main`;
- require pull request review;
- require `ci` checks;
- enable Dependabot alerts/security updates;
- enable secret scanning;
- enable private vulnerability reporting;
- configure CODEOWNERS according to the maintainer team.

## 5. First release

After sandbox contract tests and governance approval:

```bash
git tag -a v0.1.0 -m "SATUSEHAT Integration SDK v0.1.0"
git push origin v0.1.0
```

Use pre-1.0 versions while interfaces are still being stabilized. Move to `v1.0.0` after the common cross-language API contract and migration policy are formally committed.
