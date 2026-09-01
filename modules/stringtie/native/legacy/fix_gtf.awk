/^#/ {print; next}
$4>$5 { t=$4; $4=$5; $5=t }
{ print }
