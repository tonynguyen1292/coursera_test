// Serve index.html for client-side routes so a refresh on /sites or a shared
// deep link like /sites?commodity=Gold does not 404.
//
// This runs as a CloudFront Function attached to the DEFAULT behaviour only,
// which is the whole point. The obvious alternative -- distribution-level
// custom_error_response mapping 404 to /index.html -- is configured per
// distribution, not per behaviour, so it would also rewrite genuine 404s
// coming back from the API origin. This app distinguishes "the server
// rejected this request" from "the API is unreachable" (see the ApiError
// comment in frontend/src/api/client.ts), and turning an API 404 into an
// HTML page with status 200 would destroy exactly that distinction. Keeping
// the rewrite on one behaviour leaves /api/* responses untouched.
//
// Runtime is cloudfront-js-2.0. Avoid newer String methods here; indexOf is
// used rather than includes deliberately.

function handler(event) {
  var request = event.request;
  var uri = request.uri;

  // Root.
  if (uri === "/") {
    return request;
  }

  // Anything with a dot in the last path segment is a real file -- a hashed
  // JS or CSS bundle, an image, favicon.ico. Serve it as-is and let a
  // genuine miss return a genuine 404.
  var lastSegment = uri.substring(uri.lastIndexOf("/") + 1);
  if (lastSegment.indexOf(".") !== -1) {
    return request;
  }

  // Extensionless path: a client-side route. Hand it the app shell and let
  // React Router read the original URL from the browser's location, which is
  // unchanged -- only the origin request is rewritten.
  request.uri = "/index.html";
  return request;
}
