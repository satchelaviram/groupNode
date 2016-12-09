require 'socket'
require 'thread'
require 'json'
require 'fileutils'

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
$record_ip = {}
$network = nil #Graph for network topology
$full_path = nil
$full_message = {}
$file_message = {}
$circuits = {}
$ack = {}

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
            prev[node.dest].push(node.dest)
            queue[node.dest] = node.cost
            visited.push node.dest
        }

        while queue.empty? != true
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
                        prev[node.dest].push(node.dest)
                    end
                end
            }

        end

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
        if $local_ip == nil then $local_ip = cmd[0] end

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
        if $local_ip == nil then $local_ip = cmd[2] end

       $network.undir_connection($hostname, cmd[1], cmd[3].to_i, 1) 
    }
    #puts "THIS IS THE ROUTING TABLE: #{$rt}"
end

def dumptable(cmd)
    sleep($updateInterval * 2)
    file = File.open(cmd[0], 'w')
#    puts "ABOUT TO PRINT THE ROUTING TABLE: #{$rt}"
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
class Packet                                                               
    attr_accessor :unique_id, :sequence, :num_frags, :type, :data, :data_size, :src, :dest,:ttl, :path, :time_reached #for circuits

    def initialize (unique_id, sequence, num_frags, type, data, data_size, src, dest, ttl, path)
        @unique_id = unique_id
        @sequence = sequence
        @num_frags = num_frags
        @type = type
        @data = data
        @data_size = data_size
        @src = src 
        @dest = dest
        @path = path

    end
    def end_time time
        @time_reached = time
    end

    def to_json
        hash = {}
        self.instance_variables.each do |var|
            hash[var] = self.instance_variable_get var
        end
        hash.to_json
    end
    def from_json! string
        JSON.load(string).each do |var, val|
            self.instance_variable_set var, val
        end
    end
end


def sendmsg(cmd)
    uniq = Random.new
    rand = uniq.rand(1024).to_i
    size = cmd[2].bytesize
    ttl = ($nodesFile.size - 1)
    src = $hostname
    dst = cmd[1]
    msg = cmd[2]
    curr_time = $clock.to_i
    fragment = []
    counter = 0
    prev_size = 0
    max = $maxPayload
    $ack[rand] = false

    if cmd[0] == "CIRCUITM"

    else
        path = $full_path[cmd[1]]
    end


    while (size > prev_size)
        fragment[counter] = msg[prev_size, max]
        counter = counter + 1
        prev_size = max
        max = max + $maxPayload
    end 

    counter = 0

    fragment.each {|sub|
        packet = Packet.new rand, counter, fragment.size, cmd[1], sub, sub.bytesize, src, dst, ttl, path
        packet_str = packet.to_json
        packet_str.gsub! ' ','|' 
        counter = counter + 1

        client = TCPSocket.open($local_ip, $nodesFile[path[1]]["PORT"])
        client.puts("SEND #{packet_str}")
    }

end

def ftp(cmd)
    uniq = Random.new
    rand = uniq.rand(1024).to_i
    ttl = ($nodesFile.size - 1)
    src = $hostname
    dst = cmd[1]
    msg = IO.binread(cmd[2])
    size = msg.bytesize
    curr_time = $clock.to_i
    fragment = []
    counter = 0
    prev_size = 0
    max = $maxPayload
    $ack[rand] = false

    if cmd[0] == "CIRCUITM"

    else
        path = $full_path[cmd[1]]
    end

    while (size > prev_size)
        fragment[counter] = msg[prev_size, max]
        counter = counter + 1
        prev_size = max
        max = max + $maxPayload
    end 

    counter = 0

    puts "HI"

    fragment.each {|sub|
        packet = Packet.new rand, counter, fragment.size, cmd[1], sub, sub.bytesize, src, dst, ttl, path
        packet_str = packet.to_json
        packet_str.gsub! ' ','|' 
        counter = counter + 1

        client = TCPSocket.open($local_ip, $nodesFile[path[1]]["PORT"])
        client.puts("SEND2 #{packet_str} #{cmd[2]} #{cmd[3]} #{size}")

    }  
end

def file_forward(cmd)
    packet = Packet.new nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    cmd[0] = cmd[0].gsub '|', ' '
    packet.from_json! cmd[0]

    path = packet.path
    path.shift

    if($hostname == packet.dest)
        $file_message[packet.sequence.to_i] = packet.data
        if $file_message.size == 1
            time = $clock.to_i
        end
        if $file_message.size == packet.num_frags
            file_transfer(packet.src, time, cmd[1], cmd[2], cmd[3], packet.unique_id)
        end
    else
        packet_str = packet.to_json
        packet_str.gsub! ' ','|'


        client = TCPSocket.open($local_ip, $nodesFile[path[1]]["PORT"])
        client.puts("SEND2 #{packet_str} #{cmd[1]} #{cmd[2]} #{cmd[3]}")
    end
end

def file_transfer(source, time, file, dest, size, uniq)
    string = $file_message[0]
    $file_message.delete(0)

    $file_message.each{|key,value|
        string.concat(value)
    }

    f = File.new(file, "w")

    IO.binwrite(f, string)

    FileUtils.mv(f, dest)

    STDOUT.puts "FTP: #{source}-->#{dest}/#{file}"

    client = TCPSocket.open($local_ip, $nodesFile[source]["PORT"])
    client.puts("SUCCESS #{file} #{$hostname} #{time} #{size} #{uniq}")

end

def transfer_success(cmd)
    curr_time = $clock.to_i

    diff = curr_time - cmd[2].to_i

    if diff == 0
        speed = 0
    else
        speed = (cmd[3].to_i / diff.to_i)
    end

    STDOUT.puts "FTP #{cmd[0]}-->#{cmd[1]} in #{diff} at #{speed}"
    $ack[cmd[4]] = true


end



def packet_forward(cmd)

    packet = Packet.new nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    cmd[0] = cmd[0].gsub '|', ' '
    packet.from_json! cmd[0]

    path = packet.path
    path.shift


    if($hostname == packet.dest)
        $full_message[packet.sequence.to_i] = packet.data
        if $full_message.size == packet.num_frags
            print_message(packet.src, packet.unique_id)
        end
    else
        packet_str = packet.to_json
        packet_str.gsub! ' ','|'


        client = TCPSocket.open($local_ip, $nodesFile[path[1]]["PORT"])
        client.puts("SEND #{packet_str}")
    end

end

def print_message(cmd, uniq)
    string = $full_message[0]
    $full_message.delete(0)

    $full_message.each{|key,value|
        string.concat(value)
    }

    STDOUT.puts "SENDMSG: #{cmd[0]}-->#{string}"
    $ack[cmd[1]] = true

end

$pings = {}
$ping_lock = Mutex.new

def ping(cmd)
    dst = cmd[0]
    numPings = cmd[1].to_i
    delay = cmd[2].to_i
    counter = 0
    clocks = Array.new
    nexthop = $rt[dst][:nexthop]
            

    while counter < numPings


        client = TCPSocket.open($local_ip, $nodesFile[nexthop]["PORT"])
        curr_time = $clock
        packet = PingPacket.new counter, dst, curr_time, $hostname, nil
        packet_str = packet.to_json
       # puts "GENERATED STRING:#{packet_str}"
        packet_str.gsub! ' ','|' 
        client.puts("PING #{packet_str}")
        client.close
        clocks.push(curr_time) 
        counter = counter + 1
        sleep(delay)
    end
    counter = 0;

    while counter<numPings
        if $pings.has_key? counter then
            curr_ping = nil

            $ping_lock.synchronize{
                curr_ping = $pings.fetch(counter)
            }

           STDOUT.puts "#{curr_ping.sequence} #{curr_ping.dest_node} #{curr_ping.return_time.to_i - clocks[counter].to_i}" 
           counter = counter +1
        else

            if (($clock.to_i - clocks[counter].to_i) >= ping_timeout)
                STDOUT.puts "PING ERROR: HOST UNREACHABLE"
                counter = counter + 1
            end
        end
                  

    end
    
end

def ping_network(cmd)
    
    packet = PingPacket.new nil, nil, nil, nil, nil
   

    cmd[0] = cmd[0].gsub! '|', ' '
   
    
    packet.from_json! cmd[0]

    nexthop = nil
    curr_time = nil
    #If the destination has been reached
    if packet.reached_dest

        #If the packet has made it back to original node that sent ping
        if packet.origin == $hostname
            
            
            curr_time = $clock
            
            packet.end_time curr_time
            
            $ping_lock.synchronize{

                $pings[packet.sequence] = packet

            }
           
        #forward packet to origin 
        
        else

            $lock.synchronize{
                nexthop = $rt[packet.origin][:nexthop]
            }
            client = TCPSocket.open($local_ip, $nodesFile[nexthop]["PORT"])
            packet_str = packet.to_json
            packet_str.gsub! ' ','|' 
            client.puts("PING #{packet_str}")
            client.close
        end

    
    else
        #If the packet has made it to the destination
        if packet.dest_node == $hostname
            packet.made_it
            $lock.synchronize{
                nexthop = $rt[packet.origin][:nexthop]
            }
            client = TCPSocket.open($local_ip, $nodesFile[nexthop]["PORT"])
            packet_str = packet.to_json
            packet_str.gsub! ' ','|' 
            client.puts("PING #{packet_str}")
            client.close
        #forward packet to dest
        else
            $lock.synchronize{
                nexthop = $rt[packet.dest_node][:nexthop]
            }
            client = TCPSocket.open($local_ip, $nodesFile[nexthop]["PORT"])
            packet_str = packet.to_json
            packet_str.gsub! ' ','|' 
            client.puts("PING #{packet_str}")
            client.close
        end

    end
end

class PingPacket
    attr_accessor :sequence, :dest_node, :time_start, :origin, :return_time, :reached_dest, :ttl

    def initialize (sequence, dest_node, time_start, origin, return_time)
        @sequence = sequence
        @dest_node = dest_node
        @time_start = time_start
        @origin = origin
        @return_time = return_time
        @reached_dest = false
        @ttl = ($nodesFile.length * 2) + 2
    end

    def end_time time
        @return_time = time
    end

    def made_it
        @reached_dest = true
    end

    def to_json
        hash = {}
        self.instance_variables.each do |var|
            hash[var] = self.instance_variable_get var
        end
        hash.to_json
    end
    def from_json! string
        JSON.load(string).each do |var, val|
            self.instance_variable_set var, val
        end
    end
end

def traceroute(cmd)
    uniq = Random.new
    rand = uniq.rand(1024).to_i
    $ack[rand] = false
    
    path = $full_path[cmd[1]]
    
    ttl = 1
    curr_time = $clock.to_i
    hops = 0
    curr_pos = 0
    counter = 1
    continue = true

    while(continue)
        if path[counter] == cmd[1]
            continue = false
        end

        client = TCPSocket.open($local_ip, $nodesFile[path[1]]["PORT"])
        client.puts("FORWARD #{$hostname} #{$hostname} #{cmd[1]} #{curr_time} #{ttl} #{hops} #{rand}")

        counter = counter + 1
        ttl = ttl + 1
    end
end

def forward_packet(cmd)

    cmd[5] = cmd[5].to_i + 1
    path = $full_path[cmd[2]]
    ttl = cmd[4].to_i - 1 

    if(ttl == 0)   
        path = $full_path[cmd[0]]
        time = $clock.to_i - cmd[3].to_i
        nexthop = path[1]

        client = TCPSocket.open($local_ip, $nodesFile[nexthop]["PORT"])
        client.puts("TOSOURCE #{cmd[0]} #{$hostname} #{cmd[3]} #{cmd[5]} #{cmd[6]}")
    else
        nexthp = path[1]

        client = TCPSocket.open($local_ip, $nodesFile[nexthp]["PORT"])
        client.puts("FORWARD #{cmd[0]} #{$hostname} #{cmd[2]} #{cmd[3]} #{ttl} #{cmd[5]} #{cmd[6]}")
    end
end

def source_console(cmd)

    time = ($clock.to_i - cmd[2].to_i)

    if $hostname == cmd[0]
        STDOUT.puts "#{cmd[3]} #{cmd[1]} #{time}"
    else
        path = $full_path[cmd[0]]
        nexthp = path[1]

        client = TCPSocket.open($local_ip, $nodesFile[nexthp]["PORT"])
        client.puts("TOSOURCE #{cmd[0]} #{cmd[1]} #{cmd[2]} #{cmd[3]} #{cmd[4]}")
    end

end
   
#-----------------------------Part 3 --------------------------------# 
def circuitb(cmd)
    id = cmd.shift
    dest = cmd.shift
    if $circuits.has_key? id
        STDERR.puts("CIRCUIT ERROR: #{$hostname} -/-> #{dest} FAILED AT #{$hostname}")
    else
        path = cmd[0].split(',')
        curr_pos = 0
        path.unshift($hostname)
        path.push(dest)
        $circuits[id] = path
        counter = 0
        path_str = "#{$hostname}"
        path.each{ |x|

            if counter != 0  then path_str << ",#{x}" end
            counter = counter+1
        }

        curr_pos = curr_pos + 1
        client = TCPSocket.open($local_ip, $nodesFile[path[curr_pos]]["PORT"])
        client.puts("CIRCUITB2 #{id} #{dest} #{curr_pos} #{path_str} forward")
        client.close
    end
end

def circuitb_network(cmd)
    id = cmd[0]
    dest = cmd[1]
    curr_pos = cmd[2].to_i # keeps current position in the path arr
    path_str = cmd[3]
    cases = cmd[4]
    path = path_str.split(',')
    case_arr = cmd[4].split(',')

    #Forwarding the circuit
    if case_arr[0] == "forward"
        #If you have reached the destination
        if $hostname == dest
            #ERROR Dest has a circuit of same name
            if $circuits.has_key? id
                curr_pos = curr_pos-1
                client = TCPSocket.open($local_ip, $nodesFile[path[curr_pos]]["PORT"])
                client.puts("CIRCUITB2 #{id} #{dest} #{curr_pos} #{path_str} error,#{$hostname}")
                client.close
            #Success send message back
            else
                curr_pos  = curr_pos-1
                $circuits[id] = path
                STDOUT.puts "CIRCUIT #{path[0]}/#{id}í°-- > #{$hostname} over #{path.length-2}"
                client = TCPSocket.open($local_ip, $nodesFile[path[curr_pos]]["PORT"])
                client.puts("CIRCUITB2 #{id} #{dest} #{curr_pos} #{path_str} success")
                client.close

            end

        else
            #Error in hops 
            if $circuits.has_key? id
                curr_pos = curr_pos-1
                client = TCPSocket.open($local_ip, $nodesFile[path[curr_pos]]["PORT"])
                client.puts("CIRCUITB2 #{id} #{dest} #{curr_pos} #{path_str} error,#{$hostname}")
                client.close 
            #No problem keep forwarding
            else
                curr_pos  = curr_pos+1
                $circuits[id] = path 
                client = TCPSocket.open($local_ip, $nodesFile[path[curr_pos]]["PORT"])
                client.puts("CIRCUITB2 #{id} #{dest} #{curr_pos} #{path_str} forward")
                client.close
            end  
        end
    #Success
    elsif case_arr[0] == "success"
        #Reached the dest and back
        if $hostname == path[0]
            STDOUT.puts "CIRCUITB #{id} --> #{dest} over #{path.length-2}"
        #Still sending the message back
        else
            curr_pos  = curr_pos-1
            $circuits[id] = path 
            client = TCPSocket.open($local_ip, $nodesFile[path[curr_pos]]["PORT"])
            client.puts("CIRCUITB2 #{id} #{dest} #{curr_pos} #{path_str} success")
            client.close
        end
    #ERROR case
    else 
        #Error message made it back
        if $hostname == path[0]
            $circuits.delete id
           STDERR.puts "CIRCUIT ERROR: #{$hostname} -/-> #{dest} FAILED AT #{case_arr[1]}" 
        #Sending error message back
        else
                curr_pos = curr_pos-1
                $circuits.delete id
                client = TCPSocket.open($local_ip, $nodesFile[path[curr_pos]]["PORT"])
                client.puts("CIRCUITB2 #{id} #{dest} #{curr_pos} #{path_str} error,#{case_arr[1]}")
                client.close 
        end
    end

end

def circuitm(cmd)
    puts "CIRCUITS PATH IS #{circuits}"

    arr = message.split(' ')
    server_cmd = arr[0]
    args = arr[1..-1]
    #            if server_cmd != "UPDATE" then puts "THIS IS THE MESSAGE: #{message}" end

    case server_cmd


    when "EDGEB2"; edgeb_network(args)
    when "EDGEU2"; edgeu_network(args)
    when "UPDATE"; updateTable(args)
    when "TOSOURCE"; source_console(args)
    when "PING";  ping_network(args)
    when "FORWARD"; forward_packet(args)
    when "SEND"; packet_forward(args)
    when "SEND2"; file_forward(args)
    when "SUCCESS"; transfer_success(args)
    when "CIRCUITB2"; circuitb_network(args)



end

def circuitd(cmd)

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
        when "SENDMSG"; sendmsg(arr)
        when "PING"; ping(args)
        when "TRACEROUTE"; traceroute(arr)
        when "FTP"; ftp(arr)
        when "CIRCUITB"; circuitb(args)
        when "CIRCUITM"; circuitm(args)
        when "CIRCUITD"; circuitd(args)
        else STDERR.puts "ERROR: INVALID COMMAND \"#{cmd}\""
        end

    end

end



def flood()
    #Gets all the neighbors of $hostnode

    #puts "STARTING TO FLOOD"

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
    #    puts "NEIGHBORS IS EMPTY"
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
   # puts "TRYING TO UPDATE TABLE"
    sentFrom = cmd.shift
    curr_edge_time = nil
    new_edge_time = nil
    new_edge_cost = nil
    node = $node_info.new
    arr = nil
    hops = nil
    lis = nil
        loop{
            new_edge_time = cmd[3].to_i
            new_edge_cost = cmd[2].to_i

            $lock.synchronize{
                curr_edge_time = $network.get_time(cmd[0],cmd[1])
            }

            if  curr_edge_time == 0
                #name of srcNode,name of destNode,cost of edge,time of Edge
                $lock.synchronize{
                    $network.undir_connection(cmd[0], cmd[1], new_edge_time, new_edge_cost)
                }
                if ($rt.has_key?(cmd[0]) != true)
                    node.src = $hostname
                    node.dst = cmd[0]
                    node.cost = nil #do dijsktras
                    node.nexthop = nil #do dijsktras
                    $lock.synchronize{
                        $rt[cmd[0]] = node
                    }
                end 
                if($rt.has_key?(cmd[1]) != true)
                    node.src = $hostname
                    node.dst = cmd[1]
                    node.cost = nil #do dijsktras
                    node.nexthop = nil #do dijsktras
                    $lock.synchronize{
                        $rt[cmd[1]] = node
                    }
                  
                end

            elsif curr_edge_time < new_edge_time
                $lock.synchronize{
                    $network.update_cost(cmd[0], cmd[1], new_edge_time, new_edge_cost)
                }
            end       
            
            cmd.shift(4)
            break if cmd.length < 4
        
       # puts "ABOUT TO RUN DIJKSTRAS"
       $lock.synchronize{
        arr = $network.dijkstra($hostname) 
        }
        $full_path = arr[0]
        #puts "THIS IS THE RETURN OF DIJKSTRAS #{arr}" 
        $lock.synchronize{
            $rt.each_key {|key|
                update = $node_info.new 
               # puts "Key IS #{key}"
                hops = arr[0]
                lis = arr[1]
                prevs = hops[key]
                update.src = $hostname
                update.dst = key
                update.cost = lis[key]
                update.nexthop = prevs[1]
                $rt[key] = update
               # puts "ROUTING TABLE #{$rt}"
            }
        }
    }
end

#A thread that handles all incoming connections
def serverHandling()
     
    loop {
        #puts "ServerHandling thread: #{Thread.current}"
        thread = Thread.start($serv.accept) do |client|
           
            message = client.gets.chomp

            

            arr = message.split(' ')
            server_cmd = arr[0]
            args = arr[1..-1]
#            if server_cmd != "UPDATE" then puts "THIS IS THE MESSAGE: #{message}" end

            case server_cmd
            when "EDGEB2"; edgeb_network(args)
            when "EDGEU2"; edgeu_network(args)
            when "UPDATE"; updateTable(args)
            when "TOSOURCE"; source_console(args)
            when "PING";  ping_network(args)
            when "FORWARD"; forward_packet(args)
            when "SEND"; packet_forward(args)
            when "SEND2"; file_forward(args)
            when "SUCCESS"; transfer_success(args)
            when "CIRCUITB2"; circuitb_network(args)
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
        when "pingTimeout"; $ping_timeout = num
            
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


