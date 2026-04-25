* Test trailing-zero stripping logic
clear all
set more off

foreach val in 160.300 382.643 160.000 160.3 106.194 100 100.000 {
    local s = strtrim(string(`val', "%9.3f"))
    local cleaned = regexr(regexr("`s'", "0+$", ""), "\.$", "")
    display "Input: `val'  ->  formatted: '`s''  ->  cleaned: '`cleaned''"
}
