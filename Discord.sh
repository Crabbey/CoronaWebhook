#!/bin/bash
if [ -z $DISCORD_WEBHOOK ]; then
	echo "DISCORD_WEBHOOK not set, will write locally"
fi

ukpopulation=68207116
ukpopulation=54096807
data=""

function Transmit {
	curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"${data}\"}" "${DISCORD_WEBHOOK}"
}

function TransmitOnce {
	curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"${1}\"}" "${DISCORD_WEBHOOK}"
}

function addToOutput {
	newline="\n"
	if [ "${data}" == "" ]; then
		newline=""
	fi
	data="${data}${newline}${1}"
}

function fetchVaccineData {
	url='https://coronavirus.data.gov.uk/api/v1/data?filters=areaType=overview&structure=%7B%22areaType%22:%22areaType%22,%22areaName%22:%22areaName%22,%22areaCode%22:%22areaCode%22,%22date%22:%22date%22,%22newPeopleVaccinatedFirstDoseByPublishDate%22:%22newPeopleVaccinatedFirstDoseByPublishDate%22,%22newPeopleVaccinatedSecondDoseByPublishDate%22:%22newPeopleVaccinatedSecondDoseByPublishDate%22,%22cumPeopleVaccinatedFirstDoseByPublishDate%22:%22cumPeopleVaccinatedFirstDoseByPublishDate%22,%22cumPeopleVaccinatedSecondDoseByPublishDate%22:%22cumPeopleVaccinatedSecondDoseByPublishDate%22%7D&format=json'	
	datafile=$(mktemp)
	curl -q --compressed "${url}"  > $datafile
	echo ${datafile}
}

function extractDataByDate {
	file=$1
	date=$2
	echo $(cat ${file} | jq -r ".data[] | select(.date == \"${date}\")")
}

function displayNum {
	printf "%'.f" $1
}

function AttemptVaccines {
IFS='
'
	attemptno=$1
	if [ -z "$1" ]; then
		attemptno=1
	fi

	datafile=$(fetchVaccineData)
	echo ${datafile}
	dates=($(cat ${datafile} | jq -r ".data | to_entries[] | .value.date" ))
	yesterday=$(date -u +"%Y-%m-%d" --date=yesterday)
	if [[ " ${dates[@]} " =~ " ${yesterday} " ]]; then
		yesterdata=$(extractDataByDate ${datafile} ${yesterday})
		new1vac=$(echo ${yesterdata} | jq -r ".newPeopleVaccinatedFirstDoseByPublishDate")
		new2vac=$(echo ${yesterdata} | jq -r ".newPeopleVaccinatedSecondDoseByPublishDate")
		total1vac=$(echo ${yesterdata} | jq -r ".cumPeopleVaccinatedFirstDoseByPublishDate")
		total2vac=$(echo ${yesterdata} | jq -r ".cumPeopleVaccinatedSecondDoseByPublishDate")

		sevendaytotal=0
		for i in $(seq 1 7); do
			tmp=$(extractDataByDate ${datafile} $(date -u +"%Y-%m-%d" --date="${i} days ago") | jq -r '.newPeopleVaccinatedFirstDoseByPublishDate')
			sevendaytotal=$(($sevendaytotal + tmp))
		done

		eightdaytotal=0
		for i in $(seq 2 8); do
			tmp=$(extractDataByDate ${datafile} $(date -u +"%Y-%m-%d" --date="${i} days ago") | jq -r '.newPeopleVaccinatedFirstDoseByPublishDate')
			eightdaytotal=$(($eightdaytotal + tmp))
		done


		sevendaysectotal=0
		for i in $(seq 1 7); do
			tmp=$(extractDataByDate ${datafile} $(date -u +"%Y-%m-%d" --date="${i} days ago") | jq -r '.cumPeopleVaccinatedSecondDoseByPublishDate')
			sevendaysectotal=$(($sevendaytotal + tmp))
		done

		eightdaysectotal=0
		for i in $(seq 2 8); do
			tmp=$(extractDataByDate ${datafile} $(date -u +"%Y-%m-%d" --date="${i} days ago") | jq -r '.cumPeopleVaccinatedSecondDoseByPublishDate')
			eightdaysectotal=$(($eightdaytotal + tmp))
		done

		sevendayavg=$(($sevendaytotal / 7))
		eightdayavg=$(($eightdaytotal / 7))
		sevendaysecavg=$(($sevendaysectotal / 7))
		eightdaysecavg=$(($eightdaysectotal / 7))

		diff=$(printf '%.2f' $(echo "100*$sevendayavg/$eightdayavg-100" | bc -l))
		secdiff=$(printf '%.2f' $(echo "100*$sevendaysecavg/$eightdaysecavg-100" | bc -l))

		sign=""
		if [ ${eightdayavg} -lt ${sevendayavg} ]; then
			sign="+"
		fi

		secsign=""
		if [ ${eightdaysecavg} -lt ${sevendaysecavg} ]; then
			secsign="+"
		fi

		numdaysuntileveryonefirst=$(( (ukpopulation - total1vac) / sevendayavg))

		completiondate=$(date -u +"%Y-%m-%d" --date="${numdaysuntileveryonefirst} days")

		firstvacpct=$(printf '%.2f' $(echo "100*$total1vac/$ukpopulation" | bc -l))
		secondvacpct=$(printf '%.2f' $(echo "100*$total2vac/$ukpopulation" | bc -l))

		addToOutput "Data from ${yesterday}"
		addToOutput "Yesterday: 1st vaccine: $(displayNum ${new1vac}) | 2nd vaccine: $(displayNum ${new2vac})"
		addToOutput "7 day (1st vaccine): Total: $(displayNum ${sevendaytotal}) | Average: $(displayNum ${sevendayavg}) | Trend: ${sign}${diff}%"
		addToOutput "Estimated 100% 1st vaccination date: ${completiondate} (${numdaysuntileveryonefirst} days)"
		addToOutput "7 day (2nd vaccine): Total: $(displayNum ${sevendaysectotal}) | Average: $(displayNum ${sevendaysecavg}) | Trend: ${secsign}${secdiff}%"
		addToOutput "Total: 1st vaccination: $(displayNum ${total1vac}) (${firstvacpct}%) | 2nd vaccination: $(displayNum ${total2vac}) (${secondvacpct}%)"
	else
		if [ $attemptno -ge 3 ]; then
			TransmitOnce "No new data. Giving up."
			return
		fi
		TransmitOnce "No vaccine data yet, retrying in 2 hours."
		sleep 2h
		attemptno=$((attemptno+1))
		AttemptVaccines ${attemptno}
		return
	fi
}

function fetchCasesData {
	url='https://coronavirus.data.gov.uk/api/v1/data?filters=areaName=United%2520Kingdom;areaType=overview&structure=%7B%22areaType%22:%22areaType%22,%22areaName%22:%22areaName%22,%22areaCode%22:%22areaCode%22,%22date%22:%22date%22,%22newCasesByPublishDate%22:%22newCasesByPublishDate%22,%22cumCasesByPublishDate%22:%22cumCasesByPublishDate%22%7D&format=json'
	datafile=$(mktemp)
	curl -q --compressed "${url}"  > $datafile
	echo ${datafile}
}

function AttemptCases {
IFS='
'
	attemptno=$1
	if [ -z "$1" ]; then
		attemptno=1
	fi

	datafile=$(fetchCasesData)
	echo ${datafile}
	dates=($(cat ${datafile} | jq -r ".data | to_entries[] | .value.date" ))
	yesterday=$(date -u +"%Y-%m-%d" --date=yesterday)
	if [[ " ${dates[@]} " =~ " ${yesterday} " ]]; then
		# Yesterday exists
		yesterdata=$(cat ${datafile} | jq -r ".data[] | select(.date == \"${yesterday}\")")
		newcases=$(echo ${yesterdata} | jq -r ".newCasesByPublishDate")
		totalcases=$(echo ${yesterdata} | jq -r ".cumCasesByPublishDate")
	
		sevendaytotal=0
		for i in $(seq 1 7); do
			tmp=$(extractDataByDate ${datafile} $(date -u +"%Y-%m-%d" --date="${i} days ago") | jq -r '.newCasesByPublishDate')
			sevendaytotal=$(($sevendaytotal + tmp))
		done

		eightdaytotal=0
		for i in $(seq 2 8); do
			tmp=$(extractDataByDate ${datafile} $(date -u +"%Y-%m-%d" --date="${i} days ago") | jq -r '.newCasesByPublishDate')
			eightdaytotal=$(($eightdaytotal + tmp))
		done

		sevendayavg=$(($sevendaytotal / 7))
		eightdayavg=$(($eightdaytotal / 7))

		diff=$(printf '%.2f' $(echo "100*$sevendayavg/$eightdayavg-100" | bc -l))

		sign="+"
		if [ ${eightdayavg} -gt ${sevendayavg} ]; then
			sign=""
		fi

		addToOutput "New cases: $(displayNum ${newcases}) | Total cases: $(displayNum ${totalcases})"
		addToOutput "7 day new cases: Total: $(displayNum ${sevendaytotal}) | Average: $(displayNum ${sevendayavg})"
		addToOutput "7day average trend %diff: ${sign}${diff}%"
	else
		if [ $attemptno -ge 3 ]; then
			TransmitOnce "No new case data. Giving up."
			return
		fi
		TransmitOnce "No case data yet, retrying in 2 hours."
		sleep 2h
		attemptno=$((attemptno+1))
		AttemptCases ${attemptno}
		return
	fi
}

AttemptVaccines
addToOutput "--------------------------------------------"
AttemptCases
Transmit