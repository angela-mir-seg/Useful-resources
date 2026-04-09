clear
input str30 studyid y10 n10 y20 n20 nscr
"Alvarez-Urturi (2016)" 36 663 35 581 5500
"Aniwan (2017)"         11 176 11 108 2500
"Berry (2020)"          11 640  8 340 4200
"Hernandez (2014)"       5  67  5  55 1800
"Hol (2009)"            16 241 14 143 3100
"Randel (2024)"        203 3705 194 3167 45000
"Ribbing (2020)"        25 750 22 481 8000
"Van Rossum (2009)"     28 428 24 280 5000
"de Wijkerslooth (2012)" 7 121  6  72 1500
end

capture program drop meta_fit_nested
program define meta_fit_nested
    syntax , parameter(string) exp(integer) ctrl(integer) outcome(string) xlabel_diff(string asis) xlabel_ratio(string asis) [nscr(varname)]

    * 1. VALIDACIÓN Y LIMPIEZA

	local param = upper("`parameter'")
    if "`param'" == "DR" {
        local decimales 4
        if "`nscr'" == "" {
            display as error "Error: Para DR debe especificar [nscr(varname)]."
            exit
        }
    }
    else {
        local decimales 3
    }

    * Lista de variables a limpiar
    local to_drop _y_ref _n_ref _y_exp _n_exp n_total y_total n_sub y_sub n_inc y_inc ///
                 ppv_sub ppv_inc var_sub var_inc ref_val exp_val diff_val se_diff ///
                 logratio se_logratio ratio_val ratio_lcl ratio_ucl diff_lcl diff_ucl

    foreach v of local to_drop { 
		capture drop `v' 
		}

    * 2. ASIGNACIÓN DE VARIABLES SEGÚN UMBRALES
    gen double _y_ref = y`ctrl'
    gen double _n_ref = n`ctrl'
    gen double _y_exp = y`exp'
    gen double _n_exp = n`exp'
	
	

    * 3. LÓGICA DE CÁLCULO
    if "`param'" == "PPV" {
        * --- LÓGICA PARA PPV (ANIDAMIENTO EN EL DENOMINADOR) ---
        gen double n_total = max(_n_ref, _n_exp)
        gen double y_total = cond(_n_ref > _n_exp, _y_ref, _y_exp)
        gen double n_sub   = min(_n_ref, _n_exp)
        gen double y_sub   = cond(_n_ref > _n_exp, _y_exp, _y_ref)
        gen double n_inc   = n_total - n_sub
        gen double y_inc   = y_total - y_sub

        * Corrección de continuidad (Hernandez/Aniwan)
        replace y_inc = 0.5 if y_inc == 0 & n_inc > 0
        replace n_inc = n_inc + 0.5 if y_inc == 0.5
        replace y_total = y_sub + y_inc
        replace n_total = n_sub + n_inc

        gen double ppv_sub = y_sub / n_sub
        gen double ppv_inc = y_inc / n_inc
        gen double var_sub = ppv_sub * (1 - ppv_sub) / n_sub
        gen double var_inc = ppv_inc * (1 - ppv_inc) / n_inc
        
        gen double ref_val = _y_ref / _n_ref
        gen double exp_val = _y_exp / _n_exp
        
        * Diferencia PPV
        gen double diff_val = exp_val - ref_val
        gen double se_diff = sqrt( ((n_inc/n_total)^2) * (var_sub + var_inc) )
        
        * Ratio PPV (Delta Method)
        gen double ratio_val = exp_val / ref_val
        gen double logratio = log(ratio_val)
        tempvar d_sub d_inc
        gen double `d_sub' = (n_sub / (n_total * exp_val)) - (1 / ref_val) if _n_ref < _n_exp
        replace    `d_sub' = (1 / exp_val) - (n_sub / (n_total * ref_val)) if _n_ref > _n_exp
        gen double `d_inc' = (n_inc / (n_total * exp_val)) if _n_ref < _n_exp
        replace    `d_inc' = -(n_inc / (n_total * ref_val)) if _n_ref > _n_exp
        gen double se_logratio = sqrt( (`d_sub'^2)*var_sub + (`d_inc'^2)*var_inc )
    }
    
    else if "`param'" == "DR" | "`param'" == "SENS" | "`param'" == "SPEC" {
        * --- LÓGICA PARA DR (ANIDAMIENTO EN EL NUMERADOR, DENOMINADOR FIJO) ---
        gen double ref_val = _y_ref / `nscr'
        gen double exp_val = _y_exp / `nscr'
        
        gen double y_max = max(_y_exp, _y_ref)
        gen double y_min = min(_y_exp, _y_ref)
        gen double y_inc = y_max - y_min
        replace y_inc = 0.5 if y_inc == 0 // Corrección Hernandez
        
        * Diferencia DR
        gen double diff_val = exp_val - ref_val
        gen double se_diff = sqrt(y_inc) / `nscr'
        
        * Ratio DR
        gen double ratio_val = exp_val / ref_val
        gen double logratio = log(ratio_val)
        gen double se_logratio = sqrt(y_inc / (_y_exp * _y_ref))
    }
	
    * 4. INTERVALOS DE CONFIANZA 95%
    gen double diff_lcl = diff_val - 1.96 * se_diff
    gen double diff_ucl = diff_val + 1.96 * se_diff
    gen double ratio_lcl = exp(logratio - 1.96 * se_logratio)
    gen double ratio_ucl = exp(logratio + 1.96 * se_logratio)

    * 5. LISTADO
    display as text _n "Resultados por estudio para " as res upper("`parameter'")
    format ref_val exp_val diff_val ratio_val %9.4f
    list studyid ref_val exp_val diff_val diff_lcl diff_ucl ratio_val ratio_lcl ratio_ucl, noobs table

    * 6. META-ANÁLISIS CON METAN (REML)
	gsort -fullconfirmation
	label variable fullconfirmation "Confirmation"
	
	if "`parameter'" == "PPV"{
		local lcols fullconfirmation y`exp' n`exp' y`ctrl' n`ctrl'
		label variable y`exp' "TP `exp'µg/g"
		label variable y`ctrl' "TP `ctrl'µg/g"
		label variable n`exp' "No. FIT positive `exp'µg/g"
		label variable n`ctrl' "No. FIT positive `ctrl'µg/g"
	}
	if "`parameter'" == "DR"{
		local lcols fullconfirmation y`exp' y`ctrl' ntotal
		label variable y`exp' "TP `exp'µg/g"
		label variable y`ctrl' "TP `ctrl'µg/g"
		label variable ntotal "Total participants"
	}
	if "`parameter'" == "sens"{
		local parameter "sensitivity"
		local lcols y`exp' y`exp' y`ctrl' sick_partic
		local lcols_name y`exp' y`ctrl' sick_partic
		label variable y`exp' "TP `exp'µg/g"
		label variable y`ctrl' "TP `ctrl'µg/g"
		label variable sick_partic "TP+FN"
	}
	if "`parameter'" == "spec"{
		local parameter "specificity"
		local lcols y`exp' y`exp' y`ctrl' healthy_partic
		local lcols_name y`exp' y`ctrl' healthy_partic
		label variable y`exp' "TN `exp'µg/g"
		label variable y`ctrl' "TN `ctrl'µg/g"
		label variable healthy_partic "TN+FP"
	}
	
	
	if "`outcome'" == "Colorectal cancer"{
		local outcome2 "crc"
		local outcome "colorectal cancer"
	}
	if "`outcome'" == "Advanced adenoma"{
		local outcome2 "aa"
		local outcome "advanced adenoma"
	}
	
	if "`parameter'" == "PPV" | "`parameter'" == "DR" {
		metan diff_val se_diff, model(reml) lcols(studyid  `lcols') ///  
			  texts(165) astext(70) hetinfo(i2 tausq p) name(dif_`parameter'_`outcome2'_`exp'_`ctrl', replace) /// 
			  title("Difference of `parameter' in `outcome'", size(3)) subtitle("thresholds `exp'µg/g vs `ctrl'µg/g", size(3)) ///
			  caption("The threshold used as reference is `ctrl'µg/g", size(2)) ///
			  forestplot(effect("Difference in `parameter'") leftjustify xlabel(`xlabel_diff') spacing(2) ) ///
			  dp(`decimales') force  saving(tmp_data/overall_results/dif_`parameter'_`outcome'_`exp'_`ctrl'.dta, replace)
		graph export "figures\fp_`param'_dif_`outcome'_`exp'_`ctrl'.svg", as(svg) width(1200) height(800) replace
			  
		metan logratio se_logratio, model(reml) eform lcols(studyid  `lcols') ///  
			  texts(165) astext(70) hetinfo(i2 tausq p) name(ratio_`parameter'_`outcome2'_`exp'_`ctrl', replace) /// 
			  title("Ratio of `parameter' in `outcome'", size(3)) subtitle("thresholds `exp'µg/g vs `ctrl'µg/g", size(3)) ///
			  caption("The threshold used as reference is `ctrl'µg/g", size(2)) ///
			  forestplot(effect("Ratio of `parameter'") leftjustify xlabel(`xlabel_ratio') spacing(2) ) ///
			  dp(2) force  saving(tmp_data/overall_results/ratio_`parameter'_`outcome'_`exp'_`ctrl'.dta, replace)
		graph export "figures\fp_`param'_rr_`outcome'_`exp'_`ctrl'.svg", as(svg) width(1200) height(800)  replace
	}
	
	else if "`parameter'" == "sensitivity" | "`parameter'" == "specificity" {
		metan diff_val se_diff, model(reml) lcols( `lcols') ///  
		effect("Difference in `parameter'") texts(105) astext(60) ///
		hetinfo(i2 tausq p)  name(dif_`parameter'_`outcome2'_`exp'_`ctrl', replace) ///
		dp(`decimales') force xlabel(`xlabel_diff') forestplot(nobox nonote nonames savedims(A) leftjustify spacing(2))
		
		
		metan logratio se_logratio, model(reml) eform lcols( `lcols')  ///  
		effect("Ratio of `parameter'") texts(105) astext(60) ///
		hetinfo(i2 tausq p) name(ratio_`parameter'_`outcome2'_`exp'_`ctrl', replace) /// 
		dp(2) force xlabel(`xlabel_ratio')  forestplot(nobox nonote nonames usedims(A) leftjustify spacing(2))
		
		
		metan logratio se_logratio, model(reml) eform lcols( studyid `lcols_name') ///  
		effect("Ratio of `parameter'") texts(105) astext(60) ///
		hetinfo(i2 tausq p) name(name_`outcome2'_`exp'_`ctrl', replace) /// 
		dp(2) force xlabel(`xlabel_ratio')  forestplot(nobox nonote nostats nowt colsonly usedims(A) leftjustify spacing(2))
		
		
// 		forestplot _ES _LCI _UCI, nobox nonote nostats nowt colsonly lcols(studyid) texts(110) leftjustify usedims(A) name(name_`outcome2'_`exp'_`ctrl', replace)
	}
	

end
