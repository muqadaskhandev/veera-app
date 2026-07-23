import Vapor

/// Public web pages for invite deep links and Universal Links association.
struct JoinLandingController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("join", use: join)
        routes.get(".well-known", "apple-app-site-association", use: appleAppSiteAssociation)
        routes.get("apple-app-site-association", use: appleAppSiteAssociation)
    }

    /// Smart invite landing page: tries to open the iOS app, then falls back to the App Store.
    @Sendable
    func join(req: Request) async throws -> Response {
        let code = (req.query[String.self, at: "code"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        let deepLink: String
        if code.isEmpty {
            deepLink = "verraos://"
        } else {
            deepLink = "verraos://join?code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)"
        }

        let storeURL = Self.appStoreURL
        let displayCode = code.isEmpty ? "—" : code
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <meta name="apple-itunes-app" content="app-id=\(Self.appStoreID), app-argument=\(deepLink)" />
          <title>Open Verra</title>
          <style>
            :root { color-scheme: light; }
            body {
              margin: 0; min-height: 100vh; display: grid; place-items: center;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              background: #F4F1EA; color: #1A1A17; padding: 24px;
            }
            .card {
              width: min(420px, 100%); background: #fff; border-radius: 20px;
              padding: 28px 24px; box-shadow: 0 12px 40px rgba(26,26,23,0.08);
              text-align: center;
            }
            .dot { width: 12px; height: 12px; border-radius: 50%; background: #C2F23C; display: inline-block; }
            h1 { font-size: 28px; margin: 14px 0 8px; letter-spacing: -0.02em; }
            p { margin: 0 0 18px; color: #8C887E; line-height: 1.5; }
            .code {
              font-size: 22px; font-weight: 800; letter-spacing: 0.12em;
              background: #EDE9E0; border-radius: 12px; padding: 14px; margin-bottom: 18px;
            }
            a.btn {
              display: block; text-decoration: none; background: #C2F23C; color: #222417;
              font-weight: 700; border-radius: 999px; padding: 16px 18px; margin-bottom: 10px;
            }
            a.secondary { color: #8C887E; font-size: 14px; font-weight: 600; }
          </style>
        </head>
        <body>
          <div class="card">
            <span class="dot"></span>
            <h1>Open Verra</h1>
            <p>We'll open the Verra app so you can join your coach. If the app isn't installed, you'll go to the App Store.</p>
            <div class="code">\(displayCode)</div>
            <a class="btn" id="open-app" href="\(deepLink)">Open in Verra</a>
            <a class="secondary" id="app-store" href="\(storeURL)">Get Verra on the App Store</a>
          </div>
          <script>
            (function () {
              var deepLink = \(jsonString(deepLink));
              var storeURL = \(jsonString(storeURL));
              var opened = false;
              var start = Date.now();

              function goStore() {
                if (opened) return;
                if (Date.now() - start < 1200) {
                  window.location.href = storeURL;
                }
              }

              // Attempt to open the installed app via custom URL scheme.
              window.location.href = deepLink;
              setTimeout(goStore, 1600);

              document.addEventListener("visibilitychange", function () {
                if (document.hidden) opened = true;
              });
              window.addEventListener("pagehide", function () { opened = true; });
            })();
          </script>
        </body>
        </html>
        """

        var headers = HTTPHeaders()
        headers.contentType = .html
        return Response(status: .ok, headers: headers, body: .init(string: html))
    }

    /// Apple App Site Association for Universal Links (`https://…/join?code=`).
    @Sendable
    func appleAppSiteAssociation(req: Request) async throws -> Response {
        let teamID = Environment.get("APPLE_TEAM_ID")
            ?? Environment.get("APNS_TEAM_ID")
            ?? "92K48DS6BT"
        let bundleID = Environment.get("APPLE_CLIENT_ID")
            ?? Environment.get("APNS_BUNDLE_ID")
            ?? "app.rork.hiyjy25oz4yjrbssyotkw"

        let payload: [String: Any] = [
            "applinks": [
                "apps": [] as [String],
                "details": [[
                    "appID": "\(teamID).\(bundleID)",
                    "paths": ["/join", "/join/*", "/invite/*"]
                ]]
            ],
            "webcredentials": [
                "apps": ["\(teamID).\(bundleID)"]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: "application/json")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }

    private static var appStoreID: String {
        Environment.get("IOS_APP_STORE_ID") ?? "0000000000"
    }

    private static var appStoreURL: String {
        if let url = Environment.get("IOS_APP_STORE_URL"), !url.isEmpty {
            return url
        }
        let id = appStoreID
        if id != "0000000000" {
            return "https://apps.apple.com/app/id\(id)"
        }
        // Fallback until the live App Store ID is configured.
        return "https://apps.apple.com/search?term=Verra%20OS"
    }

    private func jsonString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value)) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }
}
