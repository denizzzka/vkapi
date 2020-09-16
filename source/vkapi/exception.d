module vkapi.exception;

import vibe.data.json;
import std.conv: to;

class VKException : Exception
{
    import std.exception: basicExceptionCtors;

    mixin basicExceptionCtors;
}

class VKExceptionFromRemote : VKException
{
    Json exceptionMsg;

    package this(Json errorPart, string file = __FILE__, size_t line = __LINE__)
    {
        exceptionMsg = errorPart;

        super(exceptionMsg["error_msg"].get!string, file, line);
    }
}
