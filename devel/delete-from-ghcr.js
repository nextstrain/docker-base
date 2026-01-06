// Delete Nextstrain images associated with a tagged manifest list from the
// GitHub Container registry.
//
// This file is intended for use by the GitHub action "actions/github-script".
// To use locally, set `octokit`¹ as an Octokit instance with a personal access
// token that can delete packages².
// ¹ https://github.com/octokit/core.js#authentication
// ² https://github.com/settings/tokens/new?scopes=delete:packages

module.exports = async ({octokit, tag}) => {
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

    async function deleteImage(tag) {
      const versionsWithTag = packageVersions.filter(version => version.metadata.container.tags.includes(tag));

      if (versionsWithTag.length == 0) {
        console.error(`${org}/${packageName}:${tag} was not found.`);
        errorEncountered = true;
        return;
      }

      // Each tag should only correspond to one package version.
      // Pushing an existing tag will untag the existing version and add the tag
      // to the newly pushed version.
      const versionId = versionsWithTag[0].id;
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
        }
      }
    }

    // Delete platform-specific images.
    const platforms = ["amd64", "arm64"];
    for (const platform of platforms) {
      await deleteImage(`${tag}-${platform}`);
    }

    // Delete the multi-platform image.
    await deleteImage(tag);
  }

  if (errorEncountered) {
    throw new Error(`Some package versions could not be deleted.`)
  }
}
