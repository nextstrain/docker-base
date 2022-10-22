// Delete Nextstrain images with a specific tag from the GitHub Container registry.
//
// This file is intended for use by the GitHub action "actions/github-script".
// To use locally, set `octokit`¹ as an Octokit instance with a personal access
// token that can delete packages².
// ¹ https://github.com/octokit/core.js#authentication
// ² https://github.com/settings/tokens/new?scopes=delete:packages

module.exports = async ({octokit, tag}) => {
  org = 'nextstrain';
  packages = ['base', 'base-builder'];

  for (const packageName of packages) {
    const { data: packageVersions } = await octokit.request('GET /orgs/{org}/packages/{package_type}/{package_name}/versions', {
      org: org,
      package_type: 'container',
      package_name: packageName,
    });

    const versionsWithTag = packageVersions.filter(version => version.metadata.container.tags.includes(tag));

    if (versionsWithTag.length == 0) {
      throw new Error(`${org}/${packageName}:${tag} was not found.`);
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
        } catch (deletePackageError) {
          console.log(deletePackageError);
          throw new Error(`Could not delete ${org}/${packageName}.`);
        }
      } else {
        throw new Error(`Could not delete ${org}/${packageName}:${tag}.`);
      }
    }
  }
}
