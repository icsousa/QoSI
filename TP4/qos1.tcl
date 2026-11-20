#---------------------------------------------------------------------------
# qos.tcl
#
#  ------                                                            ------
#  |Cli1|-----------                                         --------|Cli4|
#  ------    5 Mb   \                                       /  5 Mb  ------
#            5 ms    \                                     /   5 ms 
#  ------             \----           ------          ----/          ------
#  |Cli2|--------------|E1|-----------| C0 |----------|E2|-----------|Cli5|
#  ------    5 Mb     /----    5 Mb   ------   5 Mb   ----\    5 Mb  ------
#            5 ms    /        10 ms           10 ms        \   5 ms
#  ------           /                                       \        ------
#  |Cli3|-----------                                         --------|Cli6|
#  ------    5 Mb                                              5 Mb  ------
#            5 ms                                              5 ms
#
#--------------------------------------------------------------------------

#  Cria uma instancia do simulador... e define o tempo de simulacao
set ns [new Simulator]
set tempo_simulacao 15.0

# Define as opcopes de trace e os ficheiros a usar...
set trace_file [open qos1.tr w]
$ns trace-all $trace_file

$ns color 1 red
$ns color 2 green
$ns color 3 blue
$ns color 4 yellow
$ns color 5 magenta
$ns color 6 brown
set fid 1

# Cria todos os nos e ligacoes da topologia...
set Cli1 [$ns node]
set Cli2 [$ns node]
set Cli3 [$ns node]
set E1   [$ns node]
set C0   [$ns node]
set E2   [$ns node]
set Cli4 [$ns node]
set Cli5 [$ns node]
set Cli6 [$ns node]

# Ligacoes dos clientes...
$ns duplex-link $Cli1 $E1 5Mb 5ms DropTail
$ns duplex-link $Cli2 $E1 5Mb 5ms DropTail
$ns duplex-link $Cli3 $E1 5Mb 5ms DropTail
$ns duplex-link $Cli4 $E2 5Mb 5ms DropTail
$ns duplex-link $Cli5 $E2 5Mb 5ms DropTail
$ns duplex-link $Cli6 $E2 5Mb 5ms DropTail

# Ligacoes do backbone E1 - C0 - E2  (Para DiffServ)
$ns simplex-link $E1 $C0 5Mb 10ms dsRED/edge
$ns simplex-link $C0 $E1 5Mb 10ms dsRED/core
$ns simplex-link $C0 $E2 5Mb 10ms dsRED/core
$ns simplex-link $E2 $C0 5Mb 10ms dsRED/edge

# Orientacoes de posicionamento dos links para o NAM...
$ns duplex-link-op $Cli1 $E1 orient down-right
$ns duplex-link-op $Cli2 $E1 orient right
$ns duplex-link-op $Cli3 $E1 orient up-right
$ns duplex-link-op $Cli4 $E2 orient down-left
$ns duplex-link-op $Cli5 $E2 orient left
$ns duplex-link-op $Cli6 $E2 orient up-left
$ns duplex-link-op $E1 $C0 orient right
$ns duplex-link-op $C0 $E2 orient right

set q(E1C0) [[$ns link $E1 $C0] queue]
set q(E2C0) [[$ns link $E2 $C0] queue]
set q(C0E2) [[$ns link $C0 $E2] queue]
set q(C0E1) [[$ns link $C0 $E1] queue]

# Definicao dos parametros
set packetSize 1000  ;# em bytes
set cir0 2000000     ;# em bits/seg
set cbs0    5000     ;# em bytes

# Set DS RED parameters from Edge1 to Core:
$q(E1C0) meanPktSize $packetSize
$q(E1C0) set numQueues_ 1
$q(E1C0) setNumPrec 2
$q(E1C0) addPolicyEntry [$Cli1 id] [$Cli6 id] TokenBucket 10 $cir0 $cbs0
$q(E1C0) addPolicyEntry -1 -1 Dumb 11       ;# todo o restante trafego...
$q(E1C0) addPolicerEntry TokenBucket 10 11
$q(E1C0) addPolicerEntry Dumb 11
$q(E1C0) addPHBEntry 10 0 0
$q(E1C0) addPHBEntry 11 0 1
$q(E1C0) configQ 0 0 20 40 0.02
$q(E1C0) configQ 0 1 10 20 0.10

# Set DS RED parameters from Edge2 to Core:
$q(E2C0) meanPktSize $packetSize
$q(E2C0) set numQueues_ 1
$q(E2C0) setNumPrec 2
$q(E2C0) addPolicyEntry [$Cli6 id] [$Cli1 id] TokenBucket 10 $cir0 $cbs0
$q(E2C0) addPolicyEntry -1 -1 Dumb 11
$q(E2C0) addPolicerEntry TokenBucket 10 11
$q(E2C0) addPolicerEntry Dumb 11
$q(E2C0) addPHBEntry 10 0 0
$q(E2C0) addPHBEntry 11 0 1
$q(E2C0) configQ 0 0 20 40 0.02
$q(E2C0) configQ 0 1 10 20 0.10

# Set DS RED parameters from Core to Edge1:
$q(C0E1) meanPktSize $packetSize
$q(C0E1) set numQueues_ 1
$q(C0E1) setNumPrec 2
$q(C0E1) addPHBEntry 10 0 0
$q(C0E1) addPHBEntry 11 0 1
$q(C0E1) configQ 0 0 20 40 0.02
$q(C0E1) configQ 0 1 10 20 0.10

# Set DS RED parameters from Core to Edge2:
$q(C0E2) meanPktSize $packetSize
$q(C0E2) set numQueues_ 1
$q(C0E2) setNumPrec 2
$q(C0E2) addPHBEntry 10 0 0
$q(C0E2) addPHBEntry 11 0 1
$q(C0E2) configQ 0 0 20 40 0.02
$q(C0E2) configQ 0 1 10 20 0.10


# Procedimentos auxiliares: criacao de fluxos CBR...
proc cria_fluxo_CBR { origem destino tamanho_pacote debito } {
	global ns fid

	set udp [new Agent/UDP]
	$ns attach-agent $origem $udp
	set cbr [new Application/Traffic/CBR]
	$cbr attach-agent $udp
	$cbr set packet_size_ $tamanho_pacote  ;# bytes 
	$udp set packetSize_ $tamanho_pacote   ;# bytes
	$cbr set rate_ $debito                 ;# bits por segundo (bps)
	$udp set fid_ $fid
	incr fid
	set null [new Agent/Null]
	$ns attach-agent $destino $null
	$ns connect $udp $null
	return $cbr
}

# Procedimentos auxiliares: criacao de fluxos FTP...
proc cria_fluxo_FTP { origem destino tamanho_pacote } {
	global ns fid

	set tcp [new Agent/TCP]
	$ns attach-agent $origem $tcp
	set ftp [new Application/FTP]
	$ftp attach-agent $tcp
	$tcp set packetSize_ $tamanho_pacote
	set sink [new Agent/TCPSink]
	$ns attach-agent $destino $sink
	$ns connect $tcp $sink

	return $ftp
}
    
# Procedimentos auxiliares: criacao de fluxos EXP...
proc cria_fluxo_EXP { origem destino tamanho_pacote debito burst_time } {
	global ns fid

	set udp [new Agent/UDP]
	$ns attach-agent $origem $udp
	set expoo [new Application/Traffic/Exponential]
	$expoo attach-agent $udp
	$expoo set packetSize_  $tamanho_pacote  
	$expoo set burst_time_  $burst_time
	$expoo set idle_time_   [format %.1f [expr $burst_time*(1/0.4)]]
	$expoo set rate_ $debito
	$expoo set id_   $fid
	$udp set fid_    $fid
	incr fid
	set null [new Agent/Null]
	$ns attach-agent $destino $null
	$ns connect $udp $null

	return $expoo
}

proc finish {} {
    global ns trace_file

    $ns trace-annotate "Fim da Simulacao"
    close $trace_file
    exit 0
}


# Efectivar os fluxos da simulacao, incovando os procedimentos anteriores
# invocacao: cria_fluxo $No_Origem $No_Destino $tamanho_pacote $debito_bps
# comentar os que nao forem precisos...

set cbr(Cli1_Cli6)  [cria_fluxo_CBR $Cli1 $Cli6 1000 3000000]
set cbr(Cli2_Cli5)  [cria_fluxo_CBR $Cli2 $Cli5 1000 3000000]
set cbr(Cli3_Cli4)  [cria_fluxo_CBR $Cli3 $Cli4 1000 3000000]
set cbr(Cli4_Cli3)  [cria_fluxo_CBR $Cli4 $Cli3 1000 3000000]
set cbr(Cli5_Cli2)  [cria_fluxo_CBR $Cli5 $Cli2 1000 3000000]
set cbr(Cli6_Cli1)  [cria_fluxo_CBR $Cli6 $Cli1 1000 3000000]

# Imprimir, para cada QUEUE de entrada no BACKBONE, as politicas e
# os policiadores que estão definidos... (Apenas no inicio da Simulacao)

$q(E1C0) printPolicyTable
$q(E1C0) printPolicerTable

$q(E2C0) printPolicyTable
$q(E2C0) printPolicerTable
 
# Imprimir estatisticas das filas de espera de entrada em cada 10 segundos...
proc printQueueStats {} {
	global ns q
	puts "\n--------------------------------------------"
	puts "\nEstatisticas da Fila de Espera de E1 para C0"
	$q(E1C0) printStats
	puts "\nEstatisticas da Fila de Espera de C0 para E2"
	$q(C0E2) printStats
	puts "\n--------------------------------------------"

	set next_print [expr [$ns now] + 5.0]
	$ns at $next_print "printQueueStats"
}

$ns at 5.0 "printQueueStats"

# Definir as sequencias de eventos: start e stop das aplicacoes...
# Comentar conforme desejado e de acordo com os exercicios propostos...

$ns at 0.0 "$cbr(Cli1_Cli6) start"
$ns at 0.0 "$cbr(Cli2_Cli5) start"
$ns at 0.0 "$cbr(Cli3_Cli4) start"
$ns at 0.0 "$cbr(Cli4_Cli3) start"
$ns at 0.0 "$cbr(Cli5_Cli2) start"
$ns at 0.0 "$cbr(Cli6_Cli1) start"
$ns at $tempo_simulacao "$cbr(Cli1_Cli6) stop"
$ns at $tempo_simulacao "$cbr(Cli2_Cli5) stop"
$ns at $tempo_simulacao "$cbr(Cli3_Cli4) stop"
$ns at $tempo_simulacao "$cbr(Cli4_Cli3) stop"
$ns at $tempo_simulacao "$cbr(Cli5_Cli2) stop"
$ns at $tempo_simulacao "$cbr(Cli6_Cli1) stop"

# Terminar a simulacao 1 segundo depois
$ns at [expr $tempo_simulacao + 1.0] "finish"

# Correr a simulacao...
$ns run

