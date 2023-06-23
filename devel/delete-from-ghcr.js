// Delete Nextstrain images associated with a tagged manifest list from the
// GitHub Container registry.
//
// This file is intended for use by the GitHub action "actions/github-script".
// To use locally, set `octokit`¹ as an Octokit instance with a personal access
// token that can delete packages².
// ¹ https://github.com/octokit/core.js#authentication
// ² https://github.com/settings/tokens/new?scopes=delete:packages

module.exports = async ({fetch, octokit, tag, token}) => {
  org = 'nextstrain';
  packages = [
    'base',
    'base-builder-build-platform',
    'base-builder-target-platform',
  ];

  // Try all packages before terminating with any errors.
  let errorEncountered = false;

  for (const packageName of packages) {
    // First, get a list of package "version" objects containing information
    // used for deletion.
    let packageVersions;
    try {
      packageVersions = (await octokit.request('GET /orgs/{org}/packages/{package_type}/{package_name}/versions', {
        org: org,
        package_type: 'container',
        package_name: packageName,
      })).data;
    } catch (listPackageVersionsError) {
      console.log(listPackageVersionsError);
      console.error(`Could not list versions of package ${org}/${packageName}.`);
      errorEncountered = true;
      continue;
    }

    // The manifest list + one manifest per platform are pushed from the build.
    // Only the manifest list is tagged for direct removal via GitHub's REST API.

    // The GitHub REST API does not provide a way to retrieve manifest digests
    // from the manifest list, so use GHCR's (undocumented) Docker Registry API
    // to do that.
    // This works when a GitHub token with the right permissions is passed in
    // base64 form as a Bearer token¹.
    // ¹ https://github.com/orgs/community/discussions/26279#discussioncomment-3251172
    const res = await fetch(`https://ghcr.io/v2/${org}/${packageName}/manifests/${tag}`,
      {
        headers: {
          Accept: "application/vnd.docker.distribution.manifest.list.v2+json",
          Authorization: `Bearer ${btoa(token)}`
        }
      });
    const resData = await res.json();
    const manifestDigests = resData.manifests.map(manifest => manifest.digest);

    const versions = packageVersions.filter(version => manifestDigests.includes(version.name));
    for (const version of versions) {
      console.log(`Deleting the package version for ${org}/${packageName}:${version.name} ...`);
      try {
        await octokit.request('DELETE /orgs/{org}/packages/{package_type}/{package_name}/versions/{package_version_id}', {
          org: org,
          package_type: 'container',
          package_name: packageName,
          package_version_id: version.id,
        });
        console.log("Done.");
      } catch (deleteVersionError) {
        console.log(deleteVersionError);
        errorEncountered = true;
        continue;
      }
    }

    // Delete the manifest list after deleting individual manifests.

    const versionsWithTag = packageVersions.filter(version => version.metadata.container.tags.includes(tag));

    if (versionsWithTag.length == 0) {
      console.error(`${org}/${packageName}:${tag} was not found.`);
      errorEncountered = true;
      continue;
    }

    // Each tag should only correspond to one package version.
    // Pushing an existing tag will untag the existing version and add the tag
    // to the newly pushed version.
    versionId = versionsWithTag[0].id;
    console.log(`Version for ${org}/${packageName}:${tag} is ${versionId}.`);

    console.log(`Deleting the package version for ${org}/${packageName}:${tag} ...`);
    try {
      await octokit.request('DELETE /orgs/{org}/packages/{package_type}/{package_name}/versions/{package_version_id}', {
        org: org,
        package_type: 'container',
        package_name: packageName,
        package_version_id: versionId,
      });
      console.log("Done.");
    } catch (deleteVersionError) {
      console.log(deleteVersionError);

      if (deleteVersionError.response.data.message == "You cannot delete the last tagged version of a package. You must delete the package instead.") {

        // The right thing to do would be to delete the package
        // ${org}/${packageName}. However, this is a potential cause for
        // transient 403 errors¹ on GitHub Actions, so we'll keep one tagged
        // version around as a workaround until the underlying issue is fixed.
        // ¹ https://github.com/nextstrain/docker-base/issues/131
        console.log(`Not deleting ${org}/${packageName}:${tag} since that requires deleting the package.`);

      } else {
        console.error(`Could not delete ${org}/${packageName}:${tag}.`);
        errorEncountered = true;
        continue;
      }
    }
  }

  if (errorEncountered) {
    throw new Error(`Some package versions could not be deleted.`)
  }
}
