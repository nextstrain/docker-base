// Delete Nextstrain images with a specific tag from the GitHub Container registry.
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

        console.log(`Deleting the package ${org}/${packageName} ...`);
        try {
          await octokit.request('DELETE /orgs/{org}/packages/{package_type}/{package_name}', {
            org: org,
            package_type: 'container',
            package_name: packageName,
          });
          console.log("Done.");
        } catch (deletePackageError) {
          console.log(deletePackageError);
          console.error(`Could not delete ${org}/${packageName}.`);
          errorEncountered = true;
          continue;
        }
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
