module vkapi.connection;

import vibe.http.client;
import std.conv: to;
import dxml.parser;
import std.exception;
import vkapi.oauth: VkOAuthSession;
import vkapi.exception;

private auto doRawRequest(string url, string[string][] queryParams, in VkOAuthSession oAuthSession, bool isGetMethod = false)
in(oAuthSession !is null)
{
    return requestHTTP(url,
        (scope rq) {
            rq.method = isGetMethod ? HTTPMethod.GET : HTTPMethod.POST;

            // vk.com implements it's own vision of OAuth2

            queryParams ~= [
                "access_token": oAuthSession.token,
                "v": "5.122", //FIXME: should be tunable
            ];

            string[string] tmp;

            if(queryParams.length == 1)
                tmp = queryParams[0];
            else
                if(queryParams.length > 1)
                {
                    foreach(elem; queryParams)
                        foreach(param; elem.byKeyValue)
                            tmp[param.key] = param.value;
                }

            import vibe.inet.webform: formEncode;

            if(tmp.length)
            {
                if(isGetMethod)
                    rq.requestURL = rq.requestURL~'?'~tmp.formEncode;
                else
                    rq.writeFormBody(tmp);
            }
        },
    );
}

private auto doRequest(string path, string[string][] queryParams, in VkOAuthSession oAuthSession, bool isGetMethod = false)
{
    const url = `https://api.vk.com/method/`~path;

    return doRawRequest(url, queryParams, oAuthSession, isGetMethod);
}

class VKConnection
{
    import vibe.data.json;
    import vibe.stream.operations: readAll, readAllUTF8;

    private VkOAuthSession oAuthSession;

    this(VkOAuthSession s)
    {
        oAuthSession = s;
    }

    private Json callVK(string path, string[string] queryParams)
    {
        auto j = doRequest(path, [queryParams], oAuthSession).readJson;

        auto v = "error" in j;

        if(v !is null)
            throw new VKExceptionFromRemote(*v);
        else
            return j["response"];
    }

    auto getUserFoaFInfo(long user_id)
    {
        import text.xml.Parser;
        import text.xml.Decode;
        import std.encoding;
        import std.array: split;

        const url = `https://vk.com/foaf.php`;

        auto ws = cast(Windows1251String) doRawRequest(url, [["id": user_id.to!string]], oAuthSession).bodyReader.readAll;

        string res;
        transcode(ws, res);

        auto sp1 = res.split("<foaf:img>");
        auto sp2 = sp1[1].split("</foaf:img>");
        res = sp1[0]~sp2[1];

        auto range = parseXML/*!dxmlConfig*/(res);
        auto xmlNode = range.parse;

        return xmlNode.decodeXml!FoaF;
    }

    auto wallGetComment(long owner_id, long comment_id)
    {
        string[string] qa;
        qa["extended"] = "1";
        qa["fields"] = "city";
        qa["owner_id"] = owner_id.to!string;
        qa["comment_id"] = comment_id.to!string;

        return callVK("wall.getComment", qa);
    }

    auto getUserInfo(long user_id)
    {
        return callVK("users.get", ["user_id": user_id.to!string]).get!(Json[])[0].deserializeJson!UserInfo;
    }

    auto getFollowers(long user_id)
    {
        return callVK("users.getFollowers", ["user_id": user_id.to!string]).deserializeJson!Users;
    }

    auto getSubscriptions(long user_id)
    {
        return callVK("users.getSubscriptions", ["user_id": user_id.to!string]).deserializeJson!UserSubscriptions;
    }

    auto resolveScreenName(string name)
    {
        return callVK("utils.resolveScreenName", ["screen_name": name]).deserializeJson!ResolvedName;
    }

    auto getMentions(long owner_id)
    {
        return callVK("newsfeed.getMentions", ["owner_id": owner_id.to!string, "count": "50"]);
    }
}

struct UserInfo
{
    long id;
    string first_name;
    string last_name;
}

struct Users
{
    long count;
    long[] items;
}

alias UserFollowers = Users;

struct UserSubscriptions
{
    Users users;
    Users groups;
}

struct ResolvedName
{
    string type;
    long object_id;
}

struct CommentInfo
{
    string items;
}

import text.xml.Xml;
import boilerplate;
import std.datetime: SysTime;

@(Xml.Element("rdf:RDF"))
struct FoaF
{
    @(Xml.Attribute("xml:lang")) string lang;

    static struct Created
    {
        @(Xml.Attribute("dc:date"))
        SysTime date;
        alias date this;

        mixin(GenerateAll);
    }

    static struct LastLoggedIn
    {
        @(Xml.Attribute("dc:date"))
        SysTime date;
        alias date this;

        mixin(GenerateAll);
    }

    static struct Person
    {
        @(Xml.Element("foaf:name")) string name;
        @(Xml.Element("ya:firstName")) string firstName;
        @(Xml.Element("ya:secondName")) string secondName;
        @(Xml.Element("ya:created")) Created created;
        @(Xml.Element("ya:lastLoggedIn")) LastLoggedIn lastLoggedIn;

        mixin(GenerateThis);
    }

    @(Xml.Element("foaf:Person")) Person person;

    mixin(GenerateThis);
}

struct CommentCreds
{
    long wall_owner_id; /// идентификатор владельца стены (для сообществ — со знаком «минус»)
    long post_id;
    long comment_id;
}

auto parseWallPostLink(string _URL)
{
    import urlParser = url;
    import std.regex;

    try
    {
        auto parsed = urlParser.parseURL(_URL);

        enforce(
            parsed.host == "vk.com" ||
            parsed.host == "www.vk.com" ||
            parsed.host == "m.vk.com"
        );

        auto ctr = regex(`^/wall(-?\d+)_(\d+)$`, "g");
        auto r = parsed.path.matchFirst(ctr);

        CommentCreds ret;
        ret.wall_owner_id = r[1].to!long;
        ret.post_id = r[2].to!long;
        ret.comment_id = parsed.queryParams[`reply`].front.to!long;

        return ret;
    }
    catch(Exception e)
        throw new VKException("post URL isn't recognized", __FILE__, __LINE__, e);
}

unittest
{
    assert("https://vk.com/wall-2612421_1204022?reply=1204025".parseWallPostLink == CommentCreds(-2612421, 1204022, 1204025));
    assertThrown!VKException("https://vk.com/wall-2612421_1204022?reply=".parseWallPostLink);
}
