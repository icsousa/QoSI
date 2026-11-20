BEGIN {
        outf = "bw"   ;# nome da output file...
        intervalo = 1   ;# eixo dos x: intervalos de tempo...
        proximo_dump = intervalo
        s = 3
        d = 4
        # printf "Intervalo: %g Proximo dump: %g \n", intervalo proximo_dump
}
{
        if ( $1 == "r" && $3 == s && $4 == d ) {
                total_bytes += $6       ;# tamanho do pacote em bytes..
                bytes[$9"_"$10] += $6   ;# tamanho do pacote em bytes...
        }
        if ( $2 >= proximo_dump ) {
                print $2, total_bytes*8.0/intervalo > outf".gr"
                total_bytes = 0
                for ( v in bytes ) {
                    print $2, bytes[v]*8.0/intervalo > outf"_"v".gr"
                    bytes[v] = 0
                }
                proximo_dump += intervalo
        }
        last = $2
}
END {
        last_intervalo = intervalo - proximo_dump + last
        print last, total_bytes*8.0/last_intervalo > outf".gr"
        for ( v in bytes ) {
           print last, bytes[v]*8.0/last_intervalo > outf"_"v".gr"
        }
}
