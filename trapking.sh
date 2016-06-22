#!/bin/bash
#! Autore: Giordano Cetti @ Versione 1.0.0
#! IL MIO PRIMO BASH SCRIPT <3 <3 <3 { PUBBLICO :D }
#! This software has been released under the GNU GPL (https://www.gnu.org/licenses/gpl-3.0.html)
#! Lavoro svolto durante il periodo di Stage in ADS Assembly Data Systems spa


# Note di versione [ 1.0.0 ]:

# 1) Margine d'errore rispetto al tempo di ricezione traps:
# ricevendo 2 traps nello stesso secondo una delle due
# potrebbe non essere correttamente lavorata.
# Irrilevante nella maggior parte dei casi.
# In ogni caso ho voluto testare: mandando due trap nello 
# stesso secondo ho constatato che vengono elaborate entrambe.

# 2) Margine d'errore nell'implementazione di piu "AZIONI"
# Nel caso in cui vi fossero due trigger, ognuno collegato 
# ad una diversa azione, che lanciano una diversa istanza di
# questo script per lo STESSO ITEM, l'oggetto non verrebbe
# considerato.
# Modificare lo statement if relativo in caso di necessità.

# 3) Nelle trap non deve mai arrivare una pipe all'interno
# di nessuna stringa altrimenti nel momento in cui il dato
# viene elaborato, divide la stringa stessa in due righe.
# Si potrebbe risolvere nell'eventualità, utilizzando un sed
# per sostituire tutte le pipe che trova all'interno del
# value con un carattere diverso.
# Va messo prima dell'elaborazione delle righe.


# ATTENZIONE: l'utente zabbix deve poter accedere ai file temporanei in RW
# cosi come deve avere i permessi di esecuzione del presente file.
# mettere i permessi di questi files a 777 puo comunque essere una soluzione.
# essi verranno elencati nell'header delle variabili per semplicità




			### HEADER VARIABILI START ###

#	percorsi file di appoggio, creare e cambiare ownership + gruppo
idslavorati='/tmp/ids.lavorati'
sqlvalue='/tmp/in.sql'

#	zabbix db password
dbpassword='password'

#	zabbix db name
dbname='zabbix'

#	quanti oggetti considerare per la comparazione
itemsconsidered=40


			### HEADER VARIABILI END ###




#	{ITEM.VALUE1} -> $1 viene passato da zabbix.
#	Questa macro restituisce le prime righe della TRAP ricevuta,
#	purtroppo non comprende l'intero log per via della lungh max.

#	Prendo in considerazione i primi 28 caratteri di {ITEM.VALUE1}
#	che per nostra fortuna includono una data precisa al secondo.


tstmp=$(echo $1 | cut -c1-28)




#	Utilizzando i primi caratteri, eseguo una query per identificare
#	con certezza l'id dell'oggetto con quel determinato timestamp.

id=$(mysql -u root -p$dbpassword $dbname -e "SELECT id FROM history_log WHERE value LIKE CONCAT('$tstmp','%') ORDER BY id DESC LIMIT 1"|cut -f1)
id=$(echo $id | sed -n 1p)
prefix="id "
id=$(echo $id | sed "s/^$prefix//")


#	Verifico se l'id è gia stato lavorato da questo script in precedenza

if [[ "$lastid" = "$id" ]]
	then
	echo "Item ID gia lavorato precedentemente"
	exit 0
fi

lastid="$id"
lastids=$(tail -"$itemsconsidered" "$idslavorati")

flag=0
IFS=$'\n'
for next in $lastids
do
	if [[ "$id" == "$next" ]]
	then
		flag=1
	fi
done

if [ $flag -eq 1 ]

	then
	echo "Item ID gia lavorato precedentemente"
	exit 0

else	

        #       Accodo l'id nel file temporaneo ad indicare che è gia
        #       stato lavorato. Questa aggiunta dell'id lavorato è necessaria
        #       poichè zabbix tende ad eseguire piu volte la stessa "ACTION"
        #       al verificarsi di una delle condizioni("EXPRESSION") del
        #       relativo "TRIGGER".

        echo "$id" >> $idslavorati

	#	A questo punto, se l'id non era presente nella coda
	#	del file ids.lavorati, quindi eseguo la procedura che
	#	ritengo piu opportuna in base all'informazione contenuta
	#	nella trap.
	#	G: " In questo modo, possiamo sistemare sia gli oggetti che
	#	riceviamo in formato log, sia numerico, sia qualunque dei
	#	tipi di item che zabbix ci mette a disposizione. "

	#	Con una query mi faccio restituire da mysql l'intero valore
	#	della TRAP, non solamente il valore parziale che mi tornava
	#	inizialmente con {ITEM.VALUE1} ( valore decurtato )

	value=$(mysql -u root -p$dbpassword $dbname -e "SELECT value FROM history_log where id=$id")

	#       formatto la query che mi è tornata ( tolgo intestazione )

	value=$(echo $value | cut -c 7-)

	#       Scrivo questo valore in un file di appoggio

	echo "$value" > $sqlvalue
	#newvalue="ciao $value"
	
	#	nella stringa value, sostituisco i caratteri newline (\n) con
	#	una pipe in modo da lavorare l'oggetto con un separatore
	#	della lunghezza di un solo carattere invece che 2 come \n

	value=$(sed 's#\\n#|#g' <<<"$value")
	#echo $value > $sqlvalue

	#	rimuovo i doppi spazi dalle righe
	#value=$(echo $value | tr -s " ")
	#	un altro modo per farlo
	value=$(echo "$value" | sed -e 's/  */ /g' -e 's/^ *\(.*\) *$/\1/')
	


	# Comincio ad elaborare il Valore, line by line, sbizzarriamoci
	
	# nella newvalue rimetto a posto ogni riga dopo averla elaborata
	# mentre IFS indica solo il separatore utilizzato.

	newvalue=''
	IFS=$'|'

	for next in $value
	do

		# questa variabile contiene la singola riga da elaborare
		# per averla sistemata e formattata, si consiglia di non
		# bypassare mai questo step

		tmp=$(echo "$next" | sed -e 's/  */ /g' -e 's/^ *\(.*\) *$/\1/')		

		# voglio trovare la stringa relativa al
		# source ip address della trap, definisco la substringa
		
		substr='type=64 value=IpAddress: '
		
		if echo "$tmp" | grep -q "$substr"
		then
			# Se trovo la substringa, elaboro la stringa con sed:
			ipsource=$(echo "$tmp" | sed 's#.*'$substr'##g')
			# Aggiorno il valore dell'ip address 
			mysql -u root -p$dbpassword $dbname -e "UPDATE history_log SET source='$ipsource' WHERE id=$id"
		fi
		

		# A questo punto procedo a ricostruire ogni riga elaborata concatenando i valori con una pipe finale

		newvalue="$newvalue$tmp|"

		

		# sintassi if rapida per comparazione stringhe
		#if [[ "$var" == "$var" ]]
		#then
			#
		#fi

	done
	


	# Adesso converto di nuovo i separatori in newlines e rimetto
	# tutto nella variabile value, mantenendo invece le pipelines
	# nella newvalue
	
	newvalue=$(echo "${newvalue::-1}") 	# rimuove la pipe finale ;)
	echo "$newvalue" > $sqlvalue		# butto il newvalue nel file
	

	# sostituisco effettivamente le pipeline con i \n

	value=$(echo "$newvalue" | tr '|' '\n')

	
	# procedo a caricare il valore come lo voglio io sul database
	mysql -u root -p$dbpassword $dbname -e "UPDATE history_log SET value='$value' WHERE id=$id"

        # sintassi rapida per ciclare stringhe riga per riga
	#IFS=$'\n'

	#for next in $value
	#do
		#echo "$next"
	#done
	
	# sintassi rapida per ciclare files riga per riga
	#IFS=$'\n'
	#for item in `cat "$sqlvalue"`
	#do
	#	echo "Item: $item"
	#done
fi
