require 'socket'
require 'thread'

$p = nil #Port node is listening on
$hostname = nil #Nodes name
$node_info = nil #Struct for nodes rt
$rt = Hash.new #{destNode,Nodestruct}Basic Routing Table made in part 0. May be redone to graph for dijkstras
$serv = nil #Server for that handles messages from other nodes
$nodesFile = {} # A hash mapping {Node, {string, /Node info/}} from nodes file
$updateInterval = nil #update interval from config file
$maxPayload = nil #maxPayload from config file
$ping_timeout = nil #pingTimeout from config file


$clock = nil #Clock to keep the time of the program
$local_ip = nil #Local Ip given in

$lock = Mutex.new #Lock for other shared resourcesA
$record_ip = nil
$network = nil #Graph for network topology

class Connection
    attr_accessor :source, :dest, :cost , :time

    def initialize(source, dest, time, cost)
        @source = source
        @dest = dest
        @cost = cost
        @time = time
    end
end

class Network
    attr_accessor :link

    def initialize
        @link = []
    end

    def undir_connection(source, dest, time, cost)
        @link.push Connection.new source, dest, time, cost 
        @link.push Connection.new dest, source, time, cost 
    end

    def update_cost(source, dest, cost, time)
        @link.each {|node|
            if ((node.source == source && node.dest == dest) || (node.source == dest && node.dest == source))
                node.cost = cost
                node.time = time
            end
        }
    end

    def get_time(src, dest)
        @link.each {|node|
            if ((node.source == src && node.dest == dest) || (node.source == dest && node.dest == src))
                return node.time
            end
        }
        return 0

    end

    def adjacent(source)
        list = []

        @link.each {|node|
            if node.source == source
                list.push node
            end
        }

        return list
    end

    def lowest_cost(hash)
        val = 100000000
        ret = nil

        hash.each {|key, cost|
            if cost < val
                ret = key
                val = cost
            end
        }
        return ret
    end

    def remove_edge(src,dst)
        @link.each {|node|
            if ((node.source == src && node.dest == dst) || (node.source == dst && node.dest == src))
                @link.delete(node)
            end
        }
    end

    def dijkstra(source)
        dist = Hash.new
        prev = Hash.new
        queue = Hash.new
        arr = []
        visited = Array.new
        visited.push(source)

        @link.each {|node|
            if node.dest != source
                dist[node.dest] = 1000000000
                prev[node.dest] = []
            end
        }

        curr = adjacent(source)
        curr.each {|node|
            dist[node.dest] = node.cost
            prev[node.dest].unshift(source)
            queue[node.dest] = node.cost
            visited.push node.dest
        }

        puts "START PREV IS #{prev}"

        while queue.empty? != true
            puts "CURRENT PREV IS #{prev}"
            curr = lowest_cost(queue)
            queue.delete(curr)

            n = adjacent(curr)

            n.each {|node|
                if node.dest != source
                    if visited.include?(node.dest) != true
                        visited.push node.dest
                        queue[node.dest] = node.cost
                    end

                    temp = dist[curr] + node.cost

                    if temp < dist[node.dest]
                        dist[node.dest] = temp
                        prev[node.dest] = Array.new(prev[curr])
                        prev[node.dest].push(curr)
                    end
                end
            }

        end

        puts "END DISTANCE IS: #{dist}"
        puts "END PREV IS: #{prev}"

        arr[0] = prev
        arr[1] = dist

        return arr

    end
end

# --------------------- Part 0 --------------------- # 
#cmd[0] : ip of currNode 
#cmd[1] : ip of destNode
#cmd[2] : name of destNode
def edgeb_stdin(cmd)
    $record_ip[$hostname] = cmd[0]
    $record_ip[cmd[2]] = cmd[1]
    node = $node_info.new  
    time = nil
    $lock.synchronize{ 
        node.src = $hostname
        node.dst = cmd[2]
        node.cost = 1
        node.nexthop = cmd[2]
        time = $clock.to_i
        $rt[cmd[2]] = node
        if $local_ip == nil then local_ip = cmd[0] end

        $network.undir_connection($hostname, cmd[2], time, 1)
    }

    client = TCPSocket.open(cmd[1], $nodesFile[cmd[2]]["PORT"])
    client.puts("EDGEB2 #{cmd[2]} #{$hostname} #{cmd[1]} #{time}")     
    
end

#cmd[0] : name of currNode 
#cmd[1] : name of destNode
#cmd[2] : ip of currNode
#cmd[3] : time edge was made
def edgeb_network(cmd)
    node = $node_info.new 
    $lock.synchronize{
          
        node.src = $hostname
        node.dst = cmd[1]
        node.cost = 1
        node.nexthop = cmd[1]
        $rt[cmd[1]] = node
        if $local_ip == nil then local_ip = cmd[2] end

       $network.undir_connection($hostname, cmd[1], cmd[3].to_i, 1) 
    }
    puts "THIS IS THE ROUTING TABLE: #{$rt}"
end

def dumptable(cmd)
    sleep(1)
    file = File.open(cmd[0], 'w')
    puts "ABOUT TO PRINT THE ROUTING TABLE: #{$rt}"
    $lock.synchronize{
      $rt.each {|node, str| file.write "#{str[:src]},#{str[:dst]},#{str[:nexthop]},#{str[:cost]}\n"}
    }
end

def shutdown(cmd)
    STDOUT.flush
    Thread.list.each do |thread|
          thread.exit unless thread == Thread.current
    end
    exit(0)
end

# --------------------- Part 1 --------------------- #
#Dest of node to remove edge from 
def edged(cmd)
    $lock.synchronize{  
        $network.remove_edge($hostname,cmd[0])

        if $rt.has_key? cmd[0]
           $rt.delete cmd[0] 
        end

    }
end

#cmd[0] : DEST
#cmd[1] : COST
def edgeu(cmd)
    time = nil
    $lock.synchronize{
       time = $clock.to_i
        $network.update_cost($hostname, cmd[0], cmd[1].to_i, time)

        if $rt.has_key? cmd[0]
            $rt[cmd[0]][:cost] = cmd[1].to_i
        end
    } 

    client = TCPSocket.open($local_ip, $nodesFile[cmd[0]]["PORT"])
    client.puts("EDGEU2 #{$hostname} #{cmd[1]} #{time}") 
     
end

#cmd[0] : DEST
#cmd[1] : COST
#cmd[2] : Time of updated edge
def edgeu_network(cmd)
     $lock.synchronize{
        $network.update_cost($hostname, cmd[0], cmd[1].to_i,cmd[2].to_i)
        
         if $rt.has_key? cmd[0]
            $rt[cmd[0]][:cost] = cmd[1].to_i
        end
    }
end


def status()

    string = "#{$hostname},#{port}"

    neighbors = nil

    $lock.synchronize{
        neighbors = $network.adjacency
    }    
    if neighbors != nil
        neighbors.sort!
        neighbors.each {|node| string << ",#{node.dest}"} #Need to make sure this is lexical order
    end

    STDOUT.puts string
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


def flood()
    #Gets all the neighbors of $hostnode

    puts "STARTING TO FLOOD"

    neighbors = nil
    string = nil

    $lock.synchronize{
        neighbors =  $network.adjacent($hostname)
    }

    if neighbors.empty? != true

        $lock.synchronize{
            string = "UPDATE #{$hostname}"
            #Loop for building string to send to neighbors
            $network.link.each {|str| 
                if(str.dest != $hostname)
                    string << " #{str.source} #{str.dest} #{str.cost} #{str.time}"
                else  
                    string << " #{str.source} #{str.dest} #{str.cost} #{str.time}"
                end
            }
        }

        #Loop for sending the flood message to client server
        neighbors.each {|e| 
            client = TCPSocket.open($local_ip, $nodesFile[e.dest]["PORT"]) 
            client.puts string
        }
    else
        puts "NEIGHBORS IS EMPTY"
    end
end

#cmd[0] Flood message sent from probably don't need but can be used for debugging
#cmd[1] name of srcNode
#cmd[2] name of destNode
#cmd[3] cost of edge
#cmd[4] time of Edge
#Shift or delete cmd[1],cmd[2], cmd[3], cmd[4] to get the next edge src,edge dest and edge time
#******USE $rt to check if we need to change graph. will reduce the runtime********
#These are strings so remember to change to integers to_i
#Use dijkstras for next hop in $rt
def updateTable(cmd)
    puts "TRYING TO UPDATE TABLE"
    sentFrom = cmd.shift
    curr_edge_time = nil
    new_edge_time = nil
    new_edge_cost = nil
    node = $node_info.new
    arr = nil
    $lock.synchronize{
        loop{
            new_edge_time = cmd[3].to_i
            new_edge_cost = cmd[2].to_i

            
                curr_edge_time = $network.get_time(cmd[0],cmd[1])


                if  curr_edge_time == 0
                    #name of srcNode,name of destNode,cost of edge,time of Edge
                    $network.undir_connection(cmd[0], cmd[1], new_edge_time, new_edge_cost)

                    if ($rt.has_key?(cmd[0]) != true)
                        node.src = $hostname
                        node.dst = cmd[0]
                        node.cost = nil #do dijsktras
                        node.nexthop = nil #do dijsktras
                        $rt[cmd[0]] = node
                    end 
                    if($rt.has_key?(cmd[1]) != true)
                        node.src = $hostname
                        node.dst = cmd[1]
                        node.cost = nil #do dijsktras
                        node.nexthop = nil #do dijsktras
                        $rt[cmd[1]] = node
                      
                    end

                elsif curr_edge_time < new_edge_time
                    $network.update_cost(cmd[0], cmd[1], new_edge_time, new_edge_cost)
                end       
            
            cmd.shift(4)
            break if cmd.length < 4
        }
        arr = $network.dijkstra(cmd[1])  
        $rt.each{|node, str|
            if str.source == cmd[1] && str.dest == cmd[2]
                hops = arr[0].fetch(cmd[2])
                dis = arr[0].fetch(cmd[2])
                str[:nexthop] = hops[1]
                str[:cost] = dis
            end

        }
    }
        

   
}

end

#A thread that handles all incoming connections
def serverHandling()
     
    loop {
        puts "ServerHandling thread: #{Thread.current}"
        thread = Thread.start($serv.accept) do |client|
           
            message = client.gets.chomp

            puts "THIS IS THE MESSAGE: #{message}"

            arr = message.split(' ')
            server_cmd = arr[0]
            args = arr[1..-1]

            case server_cmd
            when "EDGEB2"; $nodesFile[args[1]]["SOCKET"] = client; edgeb_network(args)
            when "EDGEU2"; edgeu_network(args)
            when "UPDATE"; updateTable(args)
            else STDERR.puts "ERROR: INVALID COMMAND \"#{server_cmd}\""
            end
            client.close
        end

        
    }

end

def clockHandle()
    loop{
        sleep(1.0)
        $clock += 1
    }
end

def updateRouting()
    loop{
        sleep($updateInterval)
        flood()
    }
end

def setup(hostname, port, nodes, config)
    #set up ports, server, buffers
    puts "Hostname: #{hostname}  Port: #{port.to_i}"
    $hostname = hostname
    $p = port.to_i
    $node_info = Struct.new(:src, :dst, :cost, :nexthop)
    $record_ip = Hash.new
    $network = Network.new

    $serv = TCPServer.open($p)

    #Opens nodes file and stores in a hash
    fHandle = File.open(nodes)
    while(line = fHandle.gets())
        arr = line.chomp().split(',')

        node_name = arr[0]
        node_port = arr[1]
        $nodesFile[node_name] = {}
        $nodesFile[node_name]["PORT"] = node_port.to_i
            
    end
    #Opens config file and set configurations 
    fHandle = File.open(config)
        while(line = fHandle.gets())
        arr = line.chomp().split('=')

        cmd_name = arr[0]
        num = arr[1].to_i
        case cmd_name
        when "updateInterval"; $updateInterval = num
        when "maxPayload" ; $maxPayload = num
        when "pingTimeout"; $pingTimeout = num
            
        end
      
            
    end

    $clock = Time.now

    Thread.new do
        serverHandling()
    end
    Thread.new do
        clockHandle()
    end
    Thread.new do
        updateRouting()
    end   
  
    main()

end


setup(ARGV[0], ARGV[1], ARGV[2], ARGV[3])


