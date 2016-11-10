require 'socket'
require 'thread'

$p = nil
$hostname = nil
$node_info = nil
$rt = Hash.new 
$serv = nil
$nodesFile = {}
$clock = nil

# --------------------- Part 0 --------------------- # 
def edgeb_stdin(cmd)

    node = $node_info.new   
    node.src = $hostname
    node.dst = cmd[2]
    node.cost = 1
    node.nexthop = cmd[2] 
    $rt[$hostname] = node

    client = TCPSocket.open(cmd[0], $p)
    client.puts("#{cmd[2]},#{$hostname}")
    edgeb_network(cmd[0])
    client.close

end

def edgeb_network(cmd)

    thread = Thread.start($serv.accept) do |client|

        message = client.gets.chomp

        arr = message.split(/,/)
        my_name = arr[0]
        src_name = arr[1]

        node1 = $node_info.new        
        node1.src = my_name
        node1.dst = src_name
        node1.cost = 1
        node1.nexthop = src_name
        $rt[my_name] = node1
    end

    thread.join

end

def dumptable(cmd)
    file = File.open(cmd[0], 'w')
    $rt.each {|node, str| file.write "#{str[:src]},#{str[:dst]},#{str[:nexthop]},#{str[:cost]}\n"}
end

def shutdown(cmd)
    STDOUT.flush
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
        when "EDGEB"; edgeb_stdin(args)
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
    #set up ports, server, buffers
    $hostname = hostname
    $p = port.to_i
    $node_info = Struct.new(:src, :dst, :cost, :nexthop)

    $serv = TCPServer.open($p) 
    
    fHandle = File.open(nodes)
    while(line = fHandle.gets())
        arr = line.chomp().split(',')

        node_name = arr[0]
        node_port = arr[1]
        $nodesFile[node_name] = {}
        $nodesFile[node_name]["PORT"] = node_port.to_i
            
    end

    $clock = Time.now
    main()

end

setup(ARGV[0], ARGV[1], ARGV[2], ARGV[3])





