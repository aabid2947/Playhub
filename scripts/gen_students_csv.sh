#!/usr/bin/env bash
# Generates a 1000-row students CSV for stress-testing bulk import.
# Usage:
#   bash scripts/gen_students_csv.sh > /tmp/students_1000.csv
#   then: Students tab → Import CSV → pick the file → Import.
set -euo pipefail

ROWS=${1:-1000}

# Variety so the seeded data feels real.
FIRST=(Aarav Ananya Vihaan Diya Arjun Saanvi Vivaan Anika Reyansh Kiara
       Ishaan Aadhya Krishna Pari Aryan Riya Atharv Myra Kabir Aanya)
LAST=(Sharma Iyer Verma Nair Patel Reddy Singh Kumar Joshi Mehta
      Chopra Gupta Rao Bhatt Mukherjee Banerjee Pillai Khan Das Shah)
SPORT=(Cricket Football Badminton Swimming Tennis Basketball)
SKILL=(beginner intermediate advanced)
CITY=(Mumbai Delhi Bangalore Chennai Kolkata Hyderabad Pune Ahmedabad)

# Header
echo "first_name,last_name,parent_name,parent_phone,parent_email,date_of_birth,gender,sport,skill_level,city"

for ((i=1; i<=ROWS; i++)); do
  f="${FIRST[$((RANDOM % ${#FIRST[@]}))]}"
  l="${LAST[$((RANDOM % ${#LAST[@]}))]}"
  pn="${LAST[$((RANDOM % ${#LAST[@]}))]} (parent)"
  phone="98760$(printf "%05d" "$i")"
  email="parent${i}@example.invalid"
  yr=$((2010 + RANDOM % 8))
  mo=$(printf "%02d" $((1 + RANDOM % 12)))
  d=$(printf "%02d" $((1 + RANDOM % 28)))
  g=$([[ $((RANDOM % 2)) -eq 0 ]] && echo "male" || echo "female")
  sp="${SPORT[$((RANDOM % ${#SPORT[@]}))]}"
  sk="${SKILL[$((RANDOM % ${#SKILL[@]}))]}"
  c="${CITY[$((RANDOM % ${#CITY[@]}))]}"
  echo "${f}${i},${l},${pn},${phone},${email},${yr}-${mo}-${d},${g},${sp},${sk},${c}"
done
