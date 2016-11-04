$port = nil
$hostname = nil
$node_info = nil
$rt = nil
require 'socket'

# --------------------- Part 0 --------------------- # 

def edgeb(cmd)
    
    #s = Socket.new Socket::INET, Socket::SOCK_STREAM
    #s.connect Socket.pack_sockaddr_in($port, srcip)

    #serv = TCPServer.new(dstip, $port)
    #s = serv.accept

    if($rt[$hostname] != nil)
    	$rt[$hostname].nexthop = cmd[2]
    else
    	node = $node_info.new
    	node.src = $hostname
    	node.dst = cmd[2]
    	node.cost = 1
    	node.nexthop = cmd[2]
    	$rt[$hostname] = node
    end


end

def dumptable(cmd)
	file = File.open(cmd[0], 'w')
	$rt.each {|node, str| file.write "#{str[:src]},#{str[:dst]},#{str[:nexthop]},#{str[:cost]}\n"}
end

def shutdown(cmd)
    STDOUT.flush
    close(serv)
    exit(0)
end


# --------------------- Part 1 --------------------- # 
def edged(cmd)
    STDOUT.puts "EDGED: not implemented"
end

def edgew(cmd)
    STDOUT.puts "EDGEW: not implemented"
end

def status()
    STDOUT.puts "STATUS: not implemented"
end


# --------------------- Part 2 --------------------- # 
def sendmsg(cmd)
    STDOUT.puts "SENDMSG: not implemented"
end

def ping(cmd)
    STDOUT.puts "PING: not implemented"
end

def traceroute(cmd)
    STDOUT.puts "TRACEROUTE: not implemented"
end

def ftp(cmd)
    STDOUT.puts "FTP: not implemented"
end


# do main loop here.... 
def main()

    while(line = STDIN.gets())
        line = line.strip()
        arr = line.split(' ')
        cmd = arr[0]
        args = arr[1..-1]
        case cmd
        when "EDGEB"; edgeb(args)
        when "EDGED"; edged(args)
        when "EDGEW"; edgew(args)
        when "DUMPTABLE"; dumptable(args)
        when "SHUTDOWN"; shutdown(args)
        when "STATUS"; status()
        when "SENDMSG"; sendmsg(args)
        when "PING"; ping(args)
        when "TRACEROUTE"; traceroute(args)
        when "FTP"; ftp(args)
        else STDERR.puts "ERROR: INVALID COMMAND \"#{cmd}\""
        end
    end

end

def setup(hostname, port, nodes, config)
    $hostname = hostname
    $port = port
    $rt = Hash.new
    $node_info = Struct.new(:src, :dst, :cost, :nexthop)
    #set up ports, server, buffers


    

    main()

end

setup(ARGV[0], ARGV[1], ARGV[2], ARGV[3])