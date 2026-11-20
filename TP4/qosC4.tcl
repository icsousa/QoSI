#---------------------------------------------------------------------------
# qosC4.tcl  -  Tarefa C.4: politica "30% garantidos por cliente + excesso
#               reclassificado para prioridade inferior"
#
# Uso:  ns qosC4.tcl ds    -> solucao DiffServ proposta (por omissao)
#       ns qosC4.tcl rio   -> variante: 1 fila com RIO-C (2 precedencias)
#       ns qosC4.tcl be    -> mesmo trafego em Best-Effort/DropTail (referencia)
#
# Solucao (DiffServ):
#  1) Edge (E1->C0, E2->C0): um Token Bucket POR CLIENTE com CIR = 1.5 Mbps
#     (30% de 5 Mbps) e CBS = 10 pacotes. Trafego conforme -> DSCP 10;
#     excesso -> remarcado para DSCP 11 (prioridade inferior).
#  2) Duas filas fisicas em todos os routers do dominio:
#        fila 0 <- DSCP 10 (trafego garantido)
#        fila 1 <- DSCP 11 (excesso + restante trafego)
#  3) Agendador WRR com pesos 9:1 -> a fila 0 tem direito a 90% = 4.5 Mbps
#     (= 3 clientes x 1.5 Mbps). Como o WRR e' work-conserving, a capacidade
#     que a fila 0 nao usar fica disponivel para o excesso (fila 1).
#  4) RED em cada fila: limiares altos e max_p baixo na fila 0; limiares
#     baixos e max_p alto na fila 1 (o excesso e' descartado primeiro).
#
# Trafego (mesmo contrato para os 3 clientes, comportamentos diferentes):
#    Cli1 -> Cli6 : CBR 3.0 Mbps a partir de t = 0 s
#    Cli2 -> Cli5 : CBR 3.0 Mbps a partir de t = 5 s
#    Cli3 -> Cli4 : CBR 4.5 Mbps a partir de t = 10 s  (cliente "agressivo")
#---------------------------------------------------------------------------

set modo ds
if {$argc > 0} { set modo [lindex $argv 0] }

set ns [new Simulator]
set tempo_simulacao 20.0

set trace_file [open qosC4_$modo.tr w]
$ns trace-all $trace_file

$ns color 1 red
$ns color 2 green
$ns color 3 blue
set fid 1

set Cli1 [$ns node]
set Cli2 [$ns node]
set Cli3 [$ns node]
set E1   [$ns node]
set C0   [$ns node]
set E2   [$ns node]
set Cli4 [$ns node]
set Cli5 [$ns node]
set Cli6 [$ns node]

$ns duplex-link $Cli1 $E1 5Mb 5ms DropTail
$ns duplex-link $Cli2 $E1 5Mb 5ms DropTail
$ns duplex-link $Cli3 $E1 5Mb 5ms DropTail
$ns duplex-link $Cli4 $E2 5Mb 5ms DropTail
$ns duplex-link $Cli5 $E2 5Mb 5ms DropTail
$ns duplex-link $Cli6 $E2 5Mb 5ms DropTail

# ---------------- Parametros da politica ----------------
set packetSize 1000        ;# bytes
set capacidade 5000000     ;# bits/s do backbone
set cir [expr int(0.30 * $capacidade)]   ;# 1.5 Mbps garantidos por cliente
set cbs 10000              ;# bytes (10 pacotes de rajada)

if {$modo == "be"} {
    # Referencia: Best-Effort com DropTail
    $ns duplex-link $E1 $C0 5Mb 10ms DropTail
    $ns duplex-link $E2 $C0 5Mb 10ms DropTail
} else {
    $ns simplex-link $E1 $C0 5Mb 10ms dsRED/edge
    $ns simplex-link $C0 $E1 5Mb 10ms dsRED/core
    $ns simplex-link $C0 $E2 5Mb 10ms dsRED/core
    $ns simplex-link $E2 $C0 5Mb 10ms dsRED/edge

    set q(E1C0) [[$ns link $E1 $C0] queue]
    set q(E2C0) [[$ns link $E2 $C0] queue]
    set q(C0E2) [[$ns link $C0 $E2] queue]
    set q(C0E1) [[$ns link $C0 $E1] queue]

    # PHB, filas e agendador: IGUAIS em todos os routers (consistencia do dominio)
    proc config_filas { fila } {
        global packetSize modo
        $fila meanPktSize $packetSize
        if {$modo == "rio"} {
            # Variante AF classica: 1 fila fisica, 2 precedencias de descarte (RIO-C)
            $fila set numQueues_ 1
            $fila setNumPrec 2
            $fila setMREDMode RIO-C
            $fila addPHBEntry 10 0 0             ;# DSCP 10 -> fila 0, precedencia 0
            $fila addPHBEntry 11 0 1             ;# DSCP 11 -> fila 0, precedencia 1
            $fila configQ 0 0 30 45 0.02
            $fila configQ 0 1 10 20 0.10
        } else {
            # Proposta principal: 2 filas fisicas + WRR 9:1
            $fila set numQueues_ 2
            $fila setNumPrec 1
            $fila setSchedularMode WRR   ;# (sic) nome do comando no dsred.cc do NS-2
            $fila addQueueWeights 0 9            ;# 90% -> trafego garantido
            $fila addQueueWeights 1 1            ;# 10% minimo -> excesso
            $fila addPHBEntry 10 0 0             ;# DSCP 10 -> fila 0
            $fila addPHBEntry 11 1 0             ;# DSCP 11 -> fila 1
            $fila configQ 0 0 30 45 0.02         ;# RED suave (garantido)
            $fila configQ 1 0 10 20 0.10         ;# RED agressivo (excesso)
        }
    }

    # Classificacao/medicao por cliente no edge
    proc config_edge { fila pares } {
        global cir cbs
        foreach par $pares {
            $fila addPolicyEntry [[lindex $par 0] id] [[lindex $par 1] id] TokenBucket 10 $cir $cbs
        }
        $fila addPolicyEntry -1 -1 Dumb 11   ;# restante trafego -> prioridade inferior
        $fila addPolicerEntry TokenBucket 10 11
        $fila addPolicerEntry Dumb 11
        config_filas $fila
    }

    config_edge $q(E1C0) [list [list $Cli1 $Cli6] [list $Cli2 $Cli5] [list $Cli3 $Cli4]]
    config_edge $q(E2C0) [list [list $Cli6 $Cli1] [list $Cli5 $Cli2] [list $Cli4 $Cli3]]
    config_filas $q(C0E1)
    config_filas $q(C0E2)

    $q(E1C0) printPolicyTable
    $q(E1C0) printPolicerTable
}

proc cria_fluxo_CBR { origem destino tamanho_pacote debito } {
    global ns fid
    set udp [new Agent/UDP]
    $ns attach-agent $origem $udp
    set cbr [new Application/Traffic/CBR]
    $cbr attach-agent $udp
    $cbr set packet_size_ $tamanho_pacote
    $udp set packetSize_ $tamanho_pacote
    $cbr set rate_ $debito
    $udp set fid_ $fid
    incr fid
    set null [new Agent/Null]
    $ns attach-agent $destino $null
    $ns connect $udp $null
    return $cbr
}

proc finish {} {
    global ns trace_file modo q
    if {$modo != "be"} {
        puts "\nEstatisticas finais da fila E1->C0"
        $q(E1C0) printStats
    }
    close $trace_file
    exit 0
}

set cbr(1) [cria_fluxo_CBR $Cli1 $Cli6 $packetSize 3000000]
set cbr(2) [cria_fluxo_CBR $Cli2 $Cli5 $packetSize 3000000]
set cbr(3) [cria_fluxo_CBR $Cli3 $Cli4 $packetSize 4500000]

$ns at 0.0  "$cbr(1) start"
$ns at 5.0  "$cbr(2) start"
$ns at 10.0 "$cbr(3) start"
foreach i {1 2 3} { $ns at $tempo_simulacao "$cbr($i) stop" }

$ns at [expr $tempo_simulacao + 1.0] "finish"
$ns run
