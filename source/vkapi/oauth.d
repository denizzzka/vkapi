module vkapi.oauth;

import oauth.provider;
import oauth.settings;
import oauth.session: OAuthSession;
import std.typecons: BitFlags;
import std.conv: to;
import vibe.http.server;

auto vkOAuthProvider = new immutable OAuthProvider(
    "https://oauth.vk.com/authorize",
    "https://oauth.vk.com/access_token",
    BitFlags!(OAuthProvider.Option)(
        OAuthProvider.Option.clientAuthParams,
        OAuthProvider.Option.explicitRedirectUri,
        OAuthProvider.Option.tokenResponseType,
    )
);

class VkOAuthSettings : OAuthSettings
{
    this(string id, string token, string redirectURI = "http://api.vk.com/blank.html") immutable
    {
        super(vkOAuthProvider, id, token, redirectURI);
    }
}

interface VkOAuthSession
{
    string token() @property const nothrow;
}

class VkOAuthSessionAsService : VkOAuthSession
{
    private const string _token;

    this(string serviceToken)
    {
        _token = serviceToken;
    }

    string token() @property const nothrow
    {
        return _token;
    }
}

/// Useful for construct session from access_token URL
//FIXME: rename to more appropriate name
class VkOAuthSessionAsUser : OAuthSession, VkOAuthSession
{
    this(immutable OAuthSettings settings, string vkAccessTokenURL)
    {
        import vibe.data.json;
        import std.datetime;

        auto parsed = getTokenFromURL(vkAccessTokenURL);
        long expires_in = parsed.queryParams[`expires_in`].front.to!long;

        SaveData data;

        data.tokenData = Json([
            "access_token": Json(parsed.queryParams[`access_token`].front.to!string),
            "expires_in": Json(expires_in),
        ]);

        data.timestamp = Clock.currTime;

        import std.stdio;
        data.writeln;

        super(settings, data);
    }

    private static auto getTokenFromURL(string url)
    {
        import urlParser = url;
        import std.array;

        try
        {
            auto replaced = url.replaceFirst("#", "?");
            return urlParser.parseURL(replaced);
        }
        catch(Exception e)
            throw new Exception("URL isn't recognized"~url);
    }

    override string token() @property const nothrow
    {
        return super.token();
    }
}

HTTPListener startLocalHttpServer(immutable OAuthSettings s, string[] scopes)
{
    import vibe.http.router : URLRouter;
    import vibe.http.session : MemorySessionStore;

    auto router = new URLRouter;
    router.registerWebInterface(new VkLogin(s, scopes));

    auto settings = new HTTPServerSettings;
    settings.sessionStore = new MemorySessionStore;
    settings.port = 8585;

    return listenHTTP(settings, router);
}

import vibe.web.auth;
import vibe.web.web;
import oauth.webapp;

class VkLogin : OAuthWebapp
{
    private immutable OAuthSettings _oAuthSettings;
    private const string[] _scopes;

    this(immutable OAuthSettings s, string[] scopes)
    {
        _oAuthSettings = s;
        _scopes = scopes;
    }

    @path("/")
    void get_tryToLogin(scope HTTPServerRequest req, scope HTTPServerResponse res)
    {
        login(req, res, _oAuthSettings, ["v": "5.122", "revoke": "1"], _scopes);

        if (!res.headerWritten)
            res.redirect("/user_logged_from_vk");
    }
}
