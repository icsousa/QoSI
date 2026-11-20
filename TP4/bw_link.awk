# Igual ao bw.awk fornecido, mas com o link e o prefixo parametrizaveis:
#   awk -v s=5 -v d=4 -v outf=bwE2 -f bw_link.awk
BEGIN {
        if (outf == "") outf = "bw"
        if (s == "") s = 3
        if (d == "") d = 4
        intervalo = 1
        proximo_dump = intervalo
}
{
        if ( $1 == "r" && $3 == s && $4 == d ) {
                total_bytes += $6
                bytes[$9"_"$10] += $6
        }
        if ( $2 >= proximo_dump ) {
                print $2, total_bytes*8.0/intervalo > (outf ".gr")
                total_bytes = 0
                for ( v in bytes ) {
                    print $2, bytes[v]*8.0/intervalo > (outf "_" v ".gr")
                    bytes[v] = 0
                }
                proximo_dump += intervalo
        }
        last = $2
}
END {
        last_intervalo = intervalo - proximo_dump + last
        print last, total_bytes*8.0/last_intervalo > (outf ".gr")
        for ( v in bytes )
           print last, bytes[v]*8.0/last_intervalo > (outf "_" v ".gr")
}
