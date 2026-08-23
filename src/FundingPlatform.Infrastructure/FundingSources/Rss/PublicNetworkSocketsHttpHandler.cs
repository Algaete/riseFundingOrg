using System.Net;
using System.Net.Sockets;

namespace FundingPlatform.Infrastructure.FundingSources.Rss;

public static class PublicNetworkSocketsHttpHandler
{
    public static SocketsHttpHandler Create(string allowedHost)
    {
        var canonicalHost = allowedHost.ToLowerInvariant();
        return new SocketsHttpHandler
        {
            AllowAutoRedirect = false,
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
            ConnectTimeout = TimeSpan.FromSeconds(10),
            MaxConnectionsPerServer = 1,
            PooledConnectionLifetime = TimeSpan.FromMinutes(5),
            ConnectCallback = async (context, cancellationToken) =>
            {
                if (!string.Equals(
                        context.DnsEndPoint.Host, canonicalHost,
                        StringComparison.OrdinalIgnoreCase) ||
                    context.DnsEndPoint.Port != 443)
                    throw new HttpRequestException("RSS destination is not allowlisted.");

                var addresses = await Dns.GetHostAddressesAsync(
                    canonicalHost, cancellationToken);
                if (addresses.Length == 0 || addresses.Any(address => !IsPublic(address)))
                    throw new HttpRequestException("RSS destination resolved to a blocked network.");

                Exception? last = null;
                foreach (var address in addresses)
                {
                    var socket = new Socket(address.AddressFamily, SocketType.Stream, ProtocolType.Tcp)
                    {
                        NoDelay = true
                    };
                    try
                    {
                        await socket.ConnectAsync(
                            new IPEndPoint(address, context.DnsEndPoint.Port),
                            cancellationToken);
                        return new NetworkStream(socket, ownsSocket: true);
                    }
                    catch (Exception exception) when (exception is SocketException or OperationCanceledException)
                    {
                        socket.Dispose();
                        last = exception;
                        if (exception is OperationCanceledException) throw;
                    }
                }

                throw new HttpRequestException("RSS destination could not be reached.", last);
            }
        };
    }

    internal static bool IsPublic(IPAddress address)
    {
        if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();
        if (IPAddress.IsLoopback(address) || address.Equals(IPAddress.Any) ||
            address.Equals(IPAddress.IPv6Any) || address.Equals(IPAddress.None) ||
            address.Equals(IPAddress.IPv6None) || address.IsIPv6LinkLocal ||
            address.IsIPv6SiteLocal || address.IsIPv6Multicast)
            return false;
        var bytes = address.GetAddressBytes();
        if (address.AddressFamily == AddressFamily.InterNetwork)
        {
            return !(bytes[0] is 0 or 10 or 127 ||
                     bytes[0] == 169 && bytes[1] == 254 ||
                     bytes[0] == 172 && bytes[1] is >= 16 and <= 31 ||
                     bytes[0] == 100 && bytes[1] is >= 64 and <= 127 ||
                     bytes[0] == 192 && bytes[1] == 0 && bytes[2] is 0 or 2 ||
                     bytes[0] == 192 && bytes[1] == 168 ||
                     bytes[0] == 192 && bytes[1] == 88 && bytes[2] == 99 ||
                     bytes[0] == 198 && bytes[1] is 18 or 19 ||
                     bytes[0] == 198 && bytes[1] == 51 && bytes[2] == 100 ||
                     bytes[0] == 203 && bytes[1] == 0 && bytes[2] == 113 ||
                     bytes[0] >= 224);
        }

        // fc00::/7 unique-local and fe80::/10 link-local are blocked.
        if ((bytes[0] & 0xfe) == 0xfc ||
            bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 ||
            bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8 ||
            bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x00 ||
            bytes[0] == 0x3f && (bytes[1] & 0xf0) == 0xf0 ||
            bytes.Take(12).All(value => value == 0) ||
            bytes[0] == 0x00 && bytes[1] == 0x64 && bytes[2] == 0xff && bytes[3] == 0x9b)
            return false;
        return true;
    }
}
