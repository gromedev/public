$port = 80
$net = “example.com”
$range = 1..254

foreach ($r in $range)
{
$ip = “{0}.{1}” -F $net,$r

if(Test-Connection -BufferSize 32 -Count 1 -Quiet -ComputerName $ip)
{
    $socket = new-object System.Net.Sockets.TcpClient($ip, $port)

    If($socket.Connected)
    {
        "$ip listening to port $port"
        $socket.Close() }
    }
}
