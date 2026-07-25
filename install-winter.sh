#!/bin/sh
#
# Installs Winter CMS into /winter, refusing to proceed without an explicit version.
#
# Usage: install-winter.sh <version> [winter-repository-url] [storm-repository-url]
#
# STORM_VERSION is read from the environment, not passed positionally, and defaults to dev-wip/1.3.
# It only has an effect when a storm repository URL is given.
#
# The empty-version guard exists because the version arrives as a build argument. An ARG declared
# before FROM is only in scope for the FROM line, so a mistake there expands to an empty string and
# Composer silently installs the latest stable release instead of failing the build. That guard is the
# only hard guarantee here; a version that resolves to something is left to Composer, which fails on
# its own if the ref does not exist. What was installed is reported at the end so a mismatch is
# visible in the build log.

set -eu

VERSION="${1:-}"
REPOSITORY="${2:-}"
STORM_REPOSITORY="${3:-}"

# This is the guard for the ARG-scope mistake. If WINTER_VERSION is not in scope inside the build
# stage it expands to an empty string, and `composer create-project` with no version argument
# silently installs the latest stable release. Failing here makes that impossible to ship by
# accident, whatever version was asked for on the command line.
if [ -z "${VERSION}" ]; then
    echo "install-winter.sh: no Winter version given." >&2
    echo "install-winter.sh: ARG WINTER_VERSION must be declared inside the build stage, because" >&2
    echo "install-winter.sh: an ARG declared before FROM is only in scope for the FROM line." >&2
    exit 1
fi

normalise_git_url() {
    case "$1" in
        *.git) echo "$1" ;;
        *) echo "$1.git" ;;
    esac
}

if [ -n "${REPOSITORY}" ] || [ -n "${STORM_REPOSITORY}" ]; then
    # Winter declares VCS repositories whose canonical GitHub remote is SSH, and a build container
    # has no SSH keys. Rewrite those clone URLs to HTTPS for the duration of the install. Only
    # needed when building from a repository rather than from Packagist dists.
    git config --global url."https://github.com/".insteadOf "git@github.com:"
fi

if [ -n "${REPOSITORY}" ]; then
    # Declared as a plain git repository rather than "vcs" so Composer clones the URL given instead
    # of resolving the host's canonical remote, which for GitHub is SSH.
    composer create-project \
        --no-progress --no-interaction --no-scripts --no-dev \
        --repository="{\"type\":\"git\",\"url\":\"$(normalise_git_url "${REPOSITORY}")\"}" \
        wintercms/winter /winter "${VERSION}"
else
    composer create-project \
        --no-progress --no-interaction --no-scripts --no-dev \
        wintercms/winter /winter "${VERSION}"
fi

# Optionally repoint the Storm library at a matching branch. Winter and Storm are developed in
# lockstep, so building an unreleased Winter branch usually means testing an unreleased Storm too.
if [ -n "${STORM_REPOSITORY}" ]; then
    composer --working-dir=/winter config repositories.storm \
        "{\"type\":\"git\",\"url\":\"$(normalise_git_url "${STORM_REPOSITORY}")\"}"

    composer --working-dir=/winter require \
        --no-progress --no-interaction --no-scripts --no-update \
        "winter/storm:${STORM_VERSION:-dev-wip/1.3}"

    composer --working-dir=/winter update winter/storm \
        --no-progress --no-interaction --no-scripts --no-dev --with-dependencies
fi

git config --global --unset-all url."https://github.com/".insteadOf 2>/dev/null || true

# Report what actually landed. wintercms/winter is the root of the created project, so Composer reports
# it as "1.0.0+no-version-set" whatever was installed; the system module is an ordinary dependency and
# does track it. A branch requirement round-trips exactly, so a mismatch there is worth warning about.
# It is a warning and not a build failure on purpose: a fork whose branch name differs from the module
# constraints it pins is a legitimate configuration, and failing it would block that for no safety gain
# the empty-version guard above does not already provide.
INSTALLED_VERSION="$(php -r '
    require "/winter/vendor/autoload.php";
    echo Composer\InstalledVersions::getPrettyVersion("winter/wn-system-module") ?? "";
')"

case "${VERSION}" in
    "${INSTALLED_VERSION}"|"v${INSTALLED_VERSION}"|"${INSTALLED_VERSION#v}")
        ;;
    dev-*)
        echo "install-winter.sh: warning: asked for '${VERSION}', system module is '${INSTALLED_VERSION}'." >&2
        ;;
    *)
        ;;
esac

php -r '
    require "/winter/vendor/autoload.php";
    foreach (["winter/storm", "laravel/framework", "laravel/octane"] as $package) {
        if (!Composer\InstalledVersions::isInstalled($package)) {
            printf("install-winter.sh: %s not installed%s", $package, PHP_EOL);
            continue;
        }
        printf(
            "install-winter.sh: %s %s @ %s%s",
            $package,
            Composer\InstalledVersions::getPrettyVersion($package),
            substr((string) Composer\InstalledVersions::getReference($package), 0, 10),
            PHP_EOL
        );
    }
'

echo "install-winter.sh: installed Winter ${VERSION}."
