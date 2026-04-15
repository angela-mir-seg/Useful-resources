**# Syntax information  --------------------------------------------------------
/*
- Objetivos: Evaluar la proporción de missing de cada variable en cada estudio
- Resultados:
	1. Matriz (mapa de calor) con el porcentaje de missing por variable y estudio
	2. Base de datos final que incluye la proporción de missing por variable
* ------------------------------------------------------------------------------*/


**# Database  ------------------------------------------------------------------
cd "C:\Users\Borja Fernandez\Desktop\To Allotey"
use "IPPIC Combined Version5.dta", clear 
* ------------------------------------------------------------------------------


**# Missing data patterns ------------------------------------------------------
replace bmi_cont = . if bmi_cont < 10 | bmi_cont > 80

* matrix 102 x 16
* rows = 102 number of studies
* col = 16 (3 + 13 variables assessed for missing data)

matrix results=J(102,16,.)
* list includes outcome variable and risk factors (and potential confounders)
local list OUTstillbirth_bin age_cont smoked_bin cocaineheroinmeth_bin histcephyper_bin histrenaldis_bin histanydiab_bin prevstillbirth_bin multiplecurrentpreg_bin bmi_cont prevhertthromb_bin  highestmated_cat prevsga_bin
* utepi_cont, umbpi_cont and  plgf_cont are systematically missing
forvalues i = 1(1)102 {
	matrix results[`i',1] = `i' 	//1. Study number
	count if studyid == `i'
	local total = r(N)				//2. Number of women
	matrix results[`i',2]=r(N)
	count if studyid == `i' & OUTstillbirth_bin == 1
	matrix results[`i',3]=r(N)		//3. Number of events (stillbirth)
	local j = 4						//4. boucle to obtain the number of missing data for each variable
	foreach var in `list' {
		count if studyid == `i' & `var' == .
		matrix results[`i',`j']=r(N)/`total'
		local j = `j' + 1
		}
}
preserve
clear
svmat results
rename (results1-results16) (studyid Total Stillbirth_freq Stillbirth mis_age_cont mis_smoked_bin mis_cocaineheroinmeth_bin mis_histcephyper_bin mis_histrenaldis_bin mis_histanydiab_bin mis_prevstillbirth_bin mis_multiplecurrentpreg_bin mis_bmi_cont mis_prevhertthromb_bin mis_highestmated_cat mis_prevsga_bin)

* studyid_rename is a file.do with the study labels 
do studyid_rename
label values studyid studyid
* Recode the study numbers into strings (using their labels)
decode studyid, generate(study)
save "Missing data IPPIC SB.dta", replace
* ------------------------------------------------------------------------------


**# Summary of missing patterns (Matrix graph) ---------------------------------
use "Missing data IPPIC SB.dta",clear

drop if Total == 0				// The study number does not exist
drop if Stillbirth == 1 		// Studies with stillbirth not recorded (=1) or systematically missing (>XX%) 
drop if Stillbirth_freq == 0 	// Studies without stillbirth events (Not estimable effect)

mkmat Stillbirth age_cont bmi_cont multiplecurrentpreg_bin histcephyper_bin histrenaldis_bin histanydiab_bin prevhertthromb_bin prevstillbirth_bin prevsga_bin smoked_bin cocaineheroinmeth_bin highestmated_cat, matrix(missing) rownames(study)
plotmatrix, m(missing) color(edkblue) xlabel(, labsize(1.2)) ylabel(, labsize(1.2) angle(0)) maxticks(100) split(0 0.0001 0.05 0.10 0.20 0.5 1) blc(white) blw(vthin) legend(size(*.4) symx(*.4) col(7) bmargin(vsmall) order(1 "No missing" 2 "<5%" 3 "5-10%" 4 "10-20%" 5 "20-50%" 6 ">50%" 7 "All missing") title(Missing data (%), size(2)) position(12))
restore
* ------------------------------------------------------------------------------


**# Final Database  ------------------------------------------------------------
merge m:1 studyid using "Missing data IPPIC SB.dta"
save "IPPIC Combined Version6.dta", replace
* ------------------------------------------------------------------------------
