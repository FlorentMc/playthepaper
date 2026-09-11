/// Where the published site lives. One place for the host name: share links,
/// share pages, the content fetch URL and the About screen all derive from it.
///
/// The site is a subdomain of commuteglance.com on its cPanel shared hosting
/// (see infra/README.md). Changing the host means changing this constant, the
/// Android app-links host in AndroidManifest.xml, the CONTENT_URL in
/// .github/workflows/edition-watch.yml, and regenerating content/share/.
const String kSiteBaseUrl = 'https://play.commuteglance.com';

const String kContentBaseUrl = '$kSiteBaseUrl/content';
