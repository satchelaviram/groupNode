require 'socket'
require 'thread'

$p = nil #Port node is listening on
$hostname = nil #Nodes name
$node_info = nil #Struct for nodes rt
$rt = Hash.new #{destNode,Nodestruct}Basic Routing Table made in part 0. May be redone to graph for dijkstras
$serv = nil #Server for that handles messages from other nodes
$nodesFile = {} # A hash mapping {srcNode, {string, /Node info/}} from nodes file
$clock = nil #Clock to keep the time of the program
$local_ip = nil #Local Ip given in
$lock = Mutex.new #Lock to ensure the program is thread safe
$record_ip = nil

# --------------------- Part 0 --------------------- # 
def edgeb_stdin(cmd)
    $record_ip[$hostname] = cmd[0]
    $record_ip[cmd[2]] = cmd[1]

    lock.synchronize{
        node = $node_info.new   
        node.src = $hostname
        node.dst = cmd[2]
        node.cost = 1
        node.nexthop = cmd[2] 
        $rt[cmd[2]] = node
        if $local_ip == nil then local_ip = cmd[0] end
    }
    client = TCPSocket.open(cmd[1], $nodesFile[cmd[2]]["PORT"])
    client.puts("EDGEB2,#{cmd[2]},#{$hostname},#{cmd[1]}")     

end

def edgeb_network(cmd)

    puts "I AM HERE"

    lock.synchronize{
        node = $node_info.new   
        node.src = $hostname
        node.dst = cmd[1]
        node.cost = 1
        node.nexthop = cmd[1] 
        $rt[cmd[1]] = node
        if $local_ip == nil then local_ip = cmd[2] end
    }
    puts "THIS IS THE ROUTING TABLE: #{$rt}"

end

def dumptable(cmd)
    sleep(1)
    file = File.open(cmd[0], 'w')
    puts "ABOUT TO PRINT THE ROUTING TABLE: #{$rt}"
    $rt.each {|node, str| file.write "#{str[:src]},#{str[:dst]},#{str[:nexthop]},#{str[:cost]}\n"}
end

def shutdown(cmd)
    STDOUT.flush
    Thread.list.each do |thread|
          thread.exit unless thread == Thread.current
    end
    exit(0)
end

# --------------------- Part 1 --------------------- # 
def edged(cmd)
    ip = record_ip[$hostname]

    $rt.each {|node, str| 
        if str[:dst] == cmd[0]
            str = nil
        end
        client = TCPSocket.open(ip, $nodesFile[str[:nexthop]]["PORT"])
        client.puts("EDGEU2,#{cmd[0]},#{cmd[1]}") 
    }
end

def edged_network(cmd)
    lock.synchronize{
        $rt.each {|node, str| 
            if str[:dst] == cmd[0]
                str = nil
            end
        }
    }
end


def edgeu(cmd)
    ip = record_ip[$hostname]

    $rt.each {|node, str| 
        if str[:dst] == cmd[0]
            str[:cost] = cmd[1]
        end
        client = TCPSocket.open(ip, $nodesFile[str[:nexthop]["PORT"])
        client.puts("EDGEU2,#{cmd[0]},#{cmd[1]}") 
    }
end

def edgeu_network(cmd)
    lock.synchronize{
        $rt.each {|node, str| 
            if str[:dst] == cmd[0]
                str[:cost] = cmd[1]
            end
        }
    }
end

def status()
=begin
    string = "#{$hostname},#{port}"
    lock.synchronize{
        $rt.each {|node, str| string << ",#{str[:dst]}"} #Need to make sure this is lexical order
    }
=end
    STDOUT.puts "STATUS: not implemented"#string
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
        puts "Main() #{Thread.current}"
        line = line.strip()
        arr = line.split(' ')
        cmd = arr[0]
        args = arr[1..-1]
        case cmd
        when "EDGEB"; edgeb_stdin(args)
        when "EDGED"; edged(args)
        when "EDGEU"; edgeu(args)
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


#A thread that handles all incoming connections
def serverHandling()
     
    loop {
        puts "ServerHandling thread: #{Thread.current}"
        thread = Thread.start($serv.accept) do |client|
           
            message = client.gets.chomp

            puts "THIS IS THE MESSAGE: #{message}"

            arr = message.split(',')
            server_cmd = arr[0]
            args = arr[1..-1]

            case server_cmd
            when "EDGEB2"; edgeb_network(args)
            when "EDGEU2"; edgeu_network(args)
            when "EDGED2"; edged_network(args)
            else STDERR.puts "ERROR: INVALID COMMAND \"#{server_cmd}\""
            end

        end

        thread.join 
    }


end





def setup(hostname, port, nodes, config)
    #set up ports, server, buffers
    puts "Hostname: #{hostname}  Port: #{port.to_i}"
    $hostname = hostname
    $p = port.to_i
    $node_info = Struct.new(:src, :dst, :cost, :nexthop)
    $record_ip = Hash.new

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

    puts "Main Thread: #{Thread.current}"

    begin
        t1 = Thread.new do
            puts "Child thread: #{Thread.current}"
            serverHandling()
        end
    end    
  
   main()
end






setup(ARGV[0], ARGV[1], ARGV[2], ARGV[3])





