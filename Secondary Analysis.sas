%LET Directory = C:\Users\&sysuserid.\Rutgers University\SHWeiss Research Group - Data Extraction\ALL SAS Libraries\Dosing - METHADOS;
%let ImportDate = %sysfunc(today(), yymmdd10.);  /* Enter the Import Date (this should be the name of the folder, and will be the name of any external reports */
%let ImportTime=%sysfunc(compress(%sysfunc(TIME(),timeampm7.),%str( :)));

libname METHADOS "&Directory.";

proc import out = METHADOS.datestoimport datafile = "&Directory/Dates to Import v2019Jun07.xlsx" DBMS = xlsx REPLACE;
run;

data METHADOS.datestoimport;
    set METHADOS.datestoimport (RENAME = (ID = Subj_ID Extraction_Date = ExtractDate_temp));
    ExtractDate = INPUT(ExtractDate_temp,MMDDYY10.);
run;

proc sort data = METHADOS.datestoimport;
    by Subj_ID;
run;

proc sort data = METHADOS.master_all;
    by Subj_ID;
run;

data METHADOS.master_allwithimportdates;
    merge METHADOS.master_all METHADOS.datestoimport;
    by Subj_ID;
run;


data METHADOS.allwithdata;
    merge METHADOS.master_allwithimportdates (in = i) SASUSER.spc_tlc_2019apr10 (RENAME = (ID = Subj_ID));
        by Subj_ID;
run;

proc printto log = "C:\Users\pja77\Rutgers University\SHWeiss Research Group - Data Extraction\ALL SAS Libraries\Logs/Secondary Analysis &ImportDate. &ImportTime..log";
run; 

data METHADOS.all_analysis;
    set METHADOS.allwithdata;
    length current $ 5;
    length DoseStatusDischarge $ 20;
    length DoseStatusDischarge_dichotomous $ 20;
    array Days[*] Days1-Days4000;
    array Dose[*] Dose1-Dose4000;
    array P[*] P1-P4000;
    array post_days[*] post_days1-post_days5000 _TEMPORARY_;
    array post_dose[*] post_dose1-post_dose5000 _TEMPORARY_;
    NumDays_MaxDose = 0;
    NumDays_PostSurvey = 1;
    daysobs_alldose = 0;
    DaysAtMax = 0;
	FORMAT MinStartDate_PostInterview MinEndDate_PostInterview MaxStartDate_PostInterview MaxEndDate_PostInterview
	  SummaryStartDate1-SummaryStartDate300 SummaryEndDate1-SummaryEndDate300
	  Increase_StartDate1-Increase_StartDate50 Increase_EndDate1-Increase_EndDate50 
	  Decrease_StartDate1-Decrease_StartDate50 Decrease_EndDate1-Decrease_EndDate50 
	  Min_StartDate Min_EndDate Max_StartDate Max_EndDate 
	  Date_of_interview__MM_DD_YYYY_ A1__DOB___MM_DD_YYYY_ LastDate 
	  IncreaseConstantStartDate  DecreaseConstantStartDate MMDDYY10.;
	  
    if Days1 = . then DELETE;
    /**** Determinig Clinic based on Subject ID - since subjects were interviewed in different locations
        (over phone, etc.), and the Data was extracted by the clinic in the Clinic ID, a determination was
        made by PJA to use CLINIC Prefixes in our analysis rather then the Location by which the questionnaire
        was done (NIA and ESS were the predecessors of the current Lennard Clinic so they will be a clinic
        of TLC ***/

    if Subj_ID =: "TLC" then clinic = "TLC";
    else if Subj_ID =: "ESS" then clinic = "TLC";
    else if Subj_ID =: "NIA" then clinic = "TLC";
    else if Subj_ID =: "SPC" then clinic = "SPC";
    else if Subj_ID =: "JSA" then clinic = "JSA";

    /**** Getting the Number of Days Post Extract for those Discharged ***/

    FinalDate = MAX(of Days[*]);

    if CURRENT = "FALSE" then do;
        NumDaysSinceExtract = "15Feb2019"D - FinalDate;
    end;

    NumDaysToday = TODAY() - FinalDate;

    if NumDaysDoseObserved = . AND NumDaysTx NE . then NumDaysDoseObserved = NumDaysTx;

    /*** CHECKING IF the new daysobs_alldose matches NumDaysDoseObserved ***/
    do i = 1 by 1 to dim(days);
        if (dose[i] >= 0) then daysobs_alldose = daysobs_alldose + 1;
        else daysobs_alldose = daysobs_alldose;
        if Dose[i] NE . THEN min_dosage = MIN(min_dosage,dose[i]);
        if Dose[i] NE . THEN max_dosage = MAX(max_dosage,dose[i]);
    end;

/*  if NumDaysDoseObserved NE Daysobs_alldose then
        PUTLOG Subj_ID " NumDaysDoseObserved " NumDaysDoseObserved "
        is not consistent with newly created DaysObs_allDose " DaysObs_allDose;
*/

    /********** Creating a new variable that checks for the maximum possible number of days that a subject
    has Methadone Dose. This includes discharges, Suboxone, and Viitriol use ****/
    NumDaysSeqObserved = 0;
    do i = 1 to dim(days);
        if days[i] > 0 then NumDaysSeqObserved = NumDaysSeqObserved + 1;
        else NumDaysSeqObserved = NumDaysSeqObserved;
    end;

    /******* As per SHW, creating two new variables in the dataset checking if someone has received
    Methadone Only or something else other than Methadone - for JSAS, the code used to code
    for Suboxone, Vivitrol, Buprenorphine, and others are considered .S, .V, and .B respectively.
    If there is a dose entry for such, then we now that the subject has received drugs other than Methadone ***/

    do i = 1 to dim(days);
        if dose[i] NE .D AND dose[i] NE .A then do;
            if dose[i] EQ .S OR dose[i] EQ .V or dose[i] EQ .B then ReceivedOtherthanMethadone = "TRUE";
            else if ReceivedOtherthanMethadone = "TRUE" then ReceivedOtherthanMethadone = "TRUE";
            else ReceivedOtherthanMethadone = "FALSE";

            if dose[i] EQ .S OR dose[i] EQ .V or dose[i] EQ .B then ReceivedOtherthanMethadone = "TRUE";
            else if ReceivedOtherthanMethadone = "TRUE" then ReceivedOtherthanMethadone = "TRUE";
            else ReceivedOtherthanMethadone = "FALSE";

            if dose[i] >= 0 then ReceivedMethadone = "TRUE";
            else if ReceivedMethadone = "TRUE" then ReceivedMethadone = "TRUE";
        end;
    end;


    /**** THIS attempts to find the global maximum and minimum of dose across the entire span of
    sequence and will output that to Max Dose and Min Dose ****/
    do i = 1 by 1 to dim(days);
        if Min_Dosage = dose[i] then do;
            if Min_StartDate = . then Min_StartDate = days[i];
            else Min_StartDate = MIN(days[i], Min_StartDate);
        end;

        if Min_Dosage = dose[i] then Min_EndDate = MAX(days[i], Min_EndDate);

        if Min_Dosage = dose[i] then NumDays_MinDose = NumDays_MinDose + 1;
        else NumDays_MinDose = NumDays_MinDose;

        if Max_Dosage = dose[i] then do;
            if Max_StartDate = . then Max_StartDate = days[i];
            else Max_StartDate = Max_StartDate;
        end;

        if Max_Dosage = dose[i] then Max_EndDate = MAX(days[i], Max_EndDate);

        if Max_Dosage = dose[i] then NumDays_MaxDose = NumDays_MaxDose + 1;
        else NumDays_MaxDose = NumDays_MaxDose;

        /*** We also try to find the dose at date of interview ***/
        if days[i] = Date_of_interview__MM_DD_YYYY_ then Dose_Interview = dose[i];
    end;

    /*** At this point, we need to consider adding consent and interview dates to a central variable for
    analysis ****/

    *if Date_of_interview__MM_DD_YYYY_ = . then Date_Study_Initiation = Date_Consent_Signed;
    if Date_of_interview__MM_DD_YYYY_ >  0 then Date_Study_Initiation = Date_of_interview__MM_DD_YYYY_;
    else Date_Study_Initiation = .;

    /*** WE now try to look at post interview (or CONSENT dates - since we have subjects who have consented
    and not interviewed) **/
    do i = 1 by 1 to dim(days);
            if days[i] > =  Date_Study_Initiation AND Date_Study_Initiation NE . then do;
                post_days[NumDays_PostSurvey] = days[i];
                post_dose[NumDays_PostSurvey] = dose[i];
                MaxDose_PostInterview = MAX(MaxDose_PostInterview, dose[i]);
                if MinDose_PostInterview = . then MinDose_PostInterview = dose[i];
                else MinDose_PostInterview = MIN(MinDose_PostInterview,dose[i]);
                NumDays_PostSurvey + 1;
            end;
    end;

    *if Date_Study_Initiation EQ . then PUTLOG "WARNING: " Subj_ID
    "Date of Interview and Consent is missing so none of the analysis for PostInterview will run!";

    if NumDays_PostSurvey > 0 then do;
        do i = 1 by 1 to NumDays_PostSurvey;
            if MinDose_PostInterview = post_dose[i] then do;
                if MinStartDate_PostInterview = . then MinStartDate_PostInterview = post_days[i];
                else MinStartDate_PostInterview = MinStartDate_PostInterview;
            end;

            if MinDose_PostInterview = post_dose[i] then MinEndDate_PostInterview = MAX(post_days[i], MinEndDate_PostInterview);

            if MaxDose_PostInterview = post_dose[i] then do;
                if MaxStartDate_PostInterview = . then MaxStartDate_PostInterview = post_days[i];
                else MaxStartDate_PostInterview = MaxStartDate_PostInterview;
            end;

            if MaxDose_PostInterview = post_dose[i] then MaxEndDate_PostInterview = MAX(post_days[i], MaxEndDate_PostInterview);
        end;
    end;

    if Daysobs_alldose > 0 then do;
        LastDate = days[daysobs_alldose];
        LastDose = dose[daysobs_alldose];
    end;
    else PUTLOG "Error in analysis for Patient ID: " Subj_ID " Look into files and see what's wrong!";

    array SummaryDose[300];
    array SummaryStartDate[300];
    array SummaryEndDate[300];

    /************* START TO CREATE ARRAY OF DOSE CHANGES ACROSS SPAN of sequence -
    CONCEPT: immediately initialize the First Date and Dose to *******************/

    SummaryStartDate[1] = Days[1];
    SummaryDose[1] = Dose[1];

    z = 1;

    /*********** RESOLVE PRIOR TO ANY MORE RUNS ********************/
        /********* CHECKING IF DOSE CHANGES DAY TO DAY ***************/

    do i = 1 to dim(days);
		if Dose[i] EQ .A OR Dose[i] EQ .D OR Dose[i] EQ .Z THEN CONTINUE;

        if SummaryDose[z] EQ Dose[i] then CONTINUE;
        else if SummaryDose[z] NE Dose[i] then do;
            SummaryEndDate[z] = Days[i-1];
            z + 1;
            SummaryDose[z] = Dose[i];
            SummaryStartDate[z] = Days[i];
        end;
		else CONTINUE;
    end;

    /**

    As per conversations with SHW, DMR, and PJA, the discussion of MIN and MAX code has been changed
    by the following code below as to appropriately account for the
    if Min_Dosage = Max_Dosage then NumDays_MintoMax = .N;

    if MaxPostInterview = MinPostInterview then NumDays_MintoMaxPost = .N;

    NumDays_MintoMax = Max_startdate - Min_startdate;
    if NumDays_MintoMax = 0 then NumDays_MintoMax = .N;
    Diff_MintoMax = Max_Dosage - min_dosage;
    if Diff_MintoMax = 0 then Diff_MintoMax = .N;

    if Diff_MintoMax > 0 and NumDays_MintoMax > 0 then Rate_MintoMax = Diff_MintoMax / NumDays_MintoMax;
    else Rate_MintoMax = .N;


    if NumDays_MintoMax < 0 then do;
        Rate_MaxtoMin = Diff_MintoMax / NumDays_MintoMax;
    end;

    if Min_Dosage = Max_Dosage then Rate_MaxtoMin = .N;

    if Rate_MintoMax > 0 then Rate_MaxtoMin = .N;
    

    /***** CHECKING FOR INCREASE/DECREASE/CONSTANT Dosages **********/

    array DoseIncrease[*] DoseIncrease1-DoseIncrease3999;
    array DoseDecrease[*] DoseDecrease1-DoseDecrease3999;
    array DoseConstant[*] DoseConstant1-DoseConstant3999;

    /***** using a look ahead increase, so the next observation is an increase,
    decrease, or constant to the current dose *****/
    do i=1 to 3999 by 1;
        if Dose[i+1] > 0 AND Dose[i] > 0 then do;
            if dose[i+1] > dose[i] then do;
                DoseIncrease[i] = 1;
                DoseDecrease[i] = 0;
                DoseConstant[i] = 0;
            end;
            else if dose[i+1] < dose[i] then do;
                DoseIncrease[i] = 0;
                DoseDecrease[i] = 1;
                DoseConstant[i] = 0;
            end;
            else if dose[i+1] = dose[i]  then do;
                DoseIncrease[i] = 0;
                DoseDecrease[i] = 0;
                DoseConstant[i] = 1;
            end;
        end;
        /***** Checking if the next observation terminates the episode, if so just impute special missing values****/
        else if dose[i + 1] EQ .D OR Dose[i] EQ .D then do;
            DoseIncrease[i] = .D;
            DoseDecrease[i] = .D;
            DoseConstant[i] = .D;
        end;
		else if dose[i + 1] EQ .Z OR Dose[i] EQ .Z then do;
            DoseIncrease[i] = .Z;
            DoseDecrease[i] = .Z;
            DoseConstant[i] = .Z;
        end;
        /************** In the situation where we have a non-zero dose, and the next dose is an absent dose,
        figure out what that dose was, and go ahead and consider no change *****************/
        else if dose[i] > 0 AND dose[i+1] EQ .A then do;
            DoseIncrease[i] = 0;
            DoseDecrease[i] = 0;
            DoseConstant[i] = 1;
        end;
        /************** In the situation where we are comparing an absent dose vs an absent dose,
        just consider no change *****************/
        else if dose[i] EQ .A AND dose[i+1] EQ .A then do;
            DoseIncrease[i] = 0;
            DoseDecrease[i] = 0;
            DoseConstant[i] = 1;
        end;
        /************** In the situation where we are comparing an absent dose and one was issued a dose the next day,
        just consider no change *****************/
        else if dose[i] EQ .A AND dose[i+1] > 0 then do;
            if Dose[i+1] > TempDose then do;
                DoseIncrease[i] = 1;
                DoseDecrease[i] = 0;
                DoseConstant[i] = 0;
            end;
            else if Dose[i+1] < TempDose then do;
                DoseIncrease[i] = 0;
                DoseDecrease[i] = 1;
                DoseConstant[i] = 0;
            end;
            else if Dose[i+1] = TempDose then do;
                DoseIncrease[i] = 0;
                DoseDecrease[i] = 0;
                DoseConstant[i] = 1;
            end;
        end;
		else if i > NumDaysSeqObserved then do;
			DoseIncrease[i] = .;
			DoseDecrease[i] = .;
			DoseConstant[i] = .;
		end;
		if _N_ < 4 then PUTLOG 
						"Subj_ID: " Subj_ID " i: " i " Date: " Days[i] 
											"Dose[i]: " Dose[i] "Dose[i+1]: " Dose[i+1]
											" DoseIncrease: " DoseIncrease[i]
											" DoseDecrease: " DoseDecrease[i]
											" DoseConstant: " DoseConstant[i];

    end;
    /******************* CHECKING FOR START/END/Initial and Final Dose of rates ************************/

    array Increase_StartDate[15];
    array Increase_EndDate[15];
    array Increase_InitialDose[15];
    array Increase_EndDose[15];

    FORMAT Increase_StartDate1-Increase_StartDate15
           Increase_EndDate1-Increase_EndDate15
			Decrease_StartDate1-Decrease_StartDate15 
			Decrease_EndDate1-Decrease_EndDate15 MMDDYY10.;

    array Decrease_StartDate[15];
    array Decrease_EndDate[15];
    array Decrease_InitialDose[15];
    array Decrease_EndDose[15];

	x=1; /*** the Increase Counter ****/
	z=1; /*** the Decrease Counter ****/
	
	inIncrease = 0;
	inDecrease = 0;
	inIncreaseConstant = 0;
	inDecreaseConstant = 0;
	

	do i = 1 to dim(DoseIncrease);
		/***** 1st Check if it's an Increase or a Decrease ***********/
		if DoseIncrease[i] = 1 and DoseDecrease[i] = 0 and DoseConstant[i] = 0 then do;
			/*** if the Increase variable hasn't been declared do so now, and initalize all Start
				and End Dates ******/
			if inDecrease = 0 and inINcrease = 0 then do;
				
				/*** as we do, intiailze the inIncrease marker, the StartDates, EndDates, and Dosages **/
				inIncrease = 1;
				if Increase_StartDate[z] = . then Increase_StartDate[z] = Days[i];
				else Increase_StartDate[z] = Increase_StartDate[z];

				if Increase_EndDate[z] = . then Increase_EndDate[z] = Days[i];
				else Increase_EndDate[z] = MAX(Increase_EndDate[z],Days[i]);
					

				if Increase_InitialDose[z] = . then do;
					if Dose[i] NE .A then Increase_InitialDose[z] = Dose[i];
					else if dose[i] EQ .A AND dose[i-1] NE .A then Increase_InitialDose[z] = Dose[i-1];
					else if dose[i] EQ .A AND dose[i-2] NE .A then Increase_InitialDose[z] = Dose[i-2];
					else if dose[i] EQ .A AND dose[i-3] NE .A then Increase_InitialDose[z] = Dose[i-3];
				end;

				AnyIncreaseAcrossTotalSequence = "TRUE";
				NoIncreaseAcrossTotalSequence = "FALSE";
				
				PUTLOG  "Subj_ID: " Subj_ID "Start: "Increase_StartDate[z]
					   "END: "Increase_EndDate[z]
						"StartDose: "Increase_InitialDose[z]
						"EndDose: "Increase_EndDose[z]
						"z: " z
						"DoseIncrease[i]: " DoseIncrease[i]
						"DoseIncrease[i+1]: " DoseIncrease[i+1]
						"inIncrease = " inIncrease
						"inINcreaseConstant: " inIncreaseConstant
						"inDecrease = " inDecrease
						"inDecreaseConstant: " inDecreaseConstant
						"Increase RecordType: Intialize StartDate and Dose";
						
			end;
			/**** if we are still in Increase, just strech the end date of the Increase_EndDate
				we also need to reset the constant values, since we are in a increase period ****/
			else if inIncrease = 1 and inIncreaseConstant = 0 then do;
			    Increase_EndDate[z] = MAX(Increase_EndDate[z],Days[i]);
			end;
			/*** If the dose is in constant, and we hit an increase, reinitalize all the variables for constant ****/
			else if inIncrease = 1 and inIncreaseConstant = 1 then do;
				IncreaseConstantStartDate = .;
				IncreaseConstantStartDose = .;
				inIncreaseConstant = 0;
				Increase_EndDate[z] = MAX(Increase_EndDate[z],Days[i]);
			end;
			/****** we probably don't need to worry about this since we know if we are in DoseIncrease and
			inIncrease is 0 then we are good to go and just continue the increment *******/
			
			/***** if inDecrease = 1 and inIncrease = 0 then we just hit an increase ********/
			else if inDecrease = 1 and inIncrease = 0 then do;
				
				/*** We need to terminate the current Decrease code before initalizing the current
				increase ***/
				
				if inDecreaseConstant = 1 then do;
					Decrease_EndDate[x] = DecreaseConstantStartDate;
					Decrease_EndDose[x] = DecreaseConstantStartDose;				
					inDecreaseConstant = 0;
				end;
				else if inDecreaseConstant = 0 then do;
					Decrease_EndDate[x] = Days[i];
					Decrease_EndDose[x] = Dose[i];
					inDecreaseConstant = 0;
				end;

				PUTLOG  "Subj_ID: " Subj_ID "Start: " Decrease_StartDate[x]
						   "END: " Decrease_EndDate[x]
							"StartDose: " Decrease_InitialDose[x]
							"EndDose: " Decrease_EndDose[x]
							"x: " x
							"DoseDecrease[i]: " DoseDecrease[i]
							"DoseDecrease[i+1]: " DoseDecrease[i+1]
							"inIncrease = " inIncrease
							"inINcreaseConstant: " inIncreaseConstant
							"inDecrease = " inDecrease
							"inDecreaseConstant: " inDecreaseConstant
							"Decrease RecordType: Decrease to Increase";
				
				inDecrease = 0;			
				x + 1;
				
				/********* again intialize the dates ***************/
				inIncrease = 1;
				if Increase_StartDate[z] = . then Increase_StartDate[z] = Days[i];
				else Increase_StartDate[z] = Increase_StartDate[z];

				if Increase_EndDate[z] = . then Increase_EndDate[z] = Days[i];
				else Increase_EndDate[z] = MAX(Increase_EndDate[z],Days[i]);
					

				if Increase_InitialDose[z] = . then do;
					if Dose[i] NE .A then Increase_InitialDose[z] = Dose[i];
					else if dose[i] EQ .A AND dose[i-1] NE .A then Increase_InitialDose[z] = dose[i-1];
					else if dose[i] EQ .A AND dose[i-2] NE .A then Increase_InitialDose[z] = Dose[i-2];
					else if dose[i] EQ .A AND dose[i-3] NE .A then Increase_InitialDose[z] = Dose[i-3];
				end;

				AnyIncreaseAcrossTotalSequence = "TRUE";
				NoIncreaseAcrossTotalSequence = "FALSE";
				
				PUTLOG  "Subj_ID: " Subj_ID "Start: "Increase_StartDate[z]
					   "END: "Increase_EndDate[z]
						"StartDose: "Increase_InitialDose[z]
						"EndDose: "Increase_EndDose[z]
						"z: " z
						"DoseIncrease[i]: " DoseIncrease[i]
						"DoseIncrease[i+1]: " DoseIncrease[i+1]
						"inIncrease = " inIncrease
						"inINcreaseConstant: " inIncreaseConstant
						"inDecrease = " inDecrease
						"inDecreaseConstant: " inDecreaseConstant
						"Increase RecordType: Intialize StartDate and Dose";

			end;
			
		end;
		
		else if DoseIncrease[i] = 0 and DoseDecrease[i] = 1 and DoseConstant[i] = 0 then do;
			if inDecrease = 0 and inINcrease = 0 then do;
				
				inDecrease = 1;
	            if Decrease_StartDate[x] = . then Decrease_StartDate[x] = Days[i];
	            else Decrease_StartDate[x] = Decrease_StartDate[x];

	            if Decrease_EndDate[x] = . then Decrease_EndDate[x] = Days[i];
	            else Decrease_EndDate[x] = MAX(Decrease_EndDate[x],Days[i]);

	            if Decrease_InitialDose[x] = . then do;
					if Dose[i] NE .A then Decrease_InitialDose[x] = Dose[i];
					else if dose[i] EQ .A AND dose[i-1] NE .A then Decrease_InitialDose[x] = Dose[i-1];
	            	else if dose[i] EQ .A AND dose[i-2] NE .A then Decrease_InitialDose[x] = Dose[i-2];
	            	else if dose[i] EQ .A AND dose[i-3] NE .A then Decrease_InitialDose[x] = Dose[i-3];
				end;
		
	 
	           Decrease_InitialDose[x] = Decrease_InitialDose[x];
	           AnyDecreaseAcrossTotalSequence = "TRUE";
	           NoDecreaseAcrossTotalSequence = "FALSE";
			   FullyConstantAcrossTotalSequence = "FALSE";

				PUTLOG  "Subj_ID: " Subj_ID "Start: " Decrease_StartDate[x]
	                   "END: " Decrease_EndDate[x]
	                    "StartDose: " Decrease_InitialDose[x]
	                    "EndDose: " Decrease_EndDose[x]
	                    "z: " x
						"DoseDecrease[i]: " DoseDecrease[i]
						"DoseDecrease[i+1]: " DoseDecrease[i+1]
						"inIncrease = " inIncrease
						"inINcreaseConstant: " inIncreaseConstant
						"inDecrease = " inDecrease
						"inDecreaseConstant: " inDecreaseConstant
	                    "Decrease RecordType: Intialize StartDate and Dose";
	        end;
			
			else if inDecrease = 1 and inDecreaseConstant = 0 then do;
			    Decrease_EndDate[x] = MAX(Decrease_EndDate[x],Days[i]);
			end;

			/*** If the dose is in constant, and we hit another decrease, reinitalize all the variables for constant ****/
			else if inDecreaseConstant = 1 AND inDecrease = 1 then do;
				DecreaseConstantStartDate = .;
				DecreaseConstantStartDose = .;
				inDecreaseConstant = 0;
				Decrease_EndDate[x] = MAX(Decrease_EndDate[x],Days[i]);
			end;
	
			else if inIncrease = 1 and inDecrease = 0 then do;
			/*** Terminate the Increase Record and Start the Decrease Record ********/ 
				/*** If last record is an increase, then terminate based on increase date ***/
				if inIncreaseConstant = 0 then do;
					Increase_EndDate[z] = Days[i];
					Increase_EndDose[z] = DOse[i];
					inIncreaseConstant = 0;
				end;
				/**** If last record is a constant value, then you need to check for temps ***/
				else if inIncreaseConstant = 1 then do;
					Increase_EndDate[z] = IncreaseConstantStartDate;
					Increase_EndDose[z] = IncreaseConstantStartDose;
					inIncreaseConstant = 0;
				end;
				/**** inIncrease gets reinitalized to 0 and increment the z counter for increases ***/
	            inIncrease = 0;
				z + 1;
			
						PUTLOG  "Subj_ID: " Subj_ID "Start: " Increase_StartDate[z]
	                   "END: " Increase_EndDate[z]
	                    "StartDose: " Increase_InitialDose[z]
	                    "EndDose: " Increase_EndDose[z]
	                    "x: " x
						"DoseDecrease[i]: " DoseDecrease[i]
						"DoseDecrease[i+1]: " DoseDecrease[i+1]
						"inIncrease = " inIncrease
						"inINcreaseConstant: " inIncreaseConstant
						"inDecrease = " inDecrease
						"inDecreaseConstant: " inDecreaseConstant
	                    "Increase RecordType: Increase to Decrease";

				/**** Deal with your decrease data now **************/
				inDecrease = 1;
	            if Decrease_StartDate[x] = . then Decrease_StartDate[z] = Days[i];
	            else Decrease_StartDate[x] = Decrease_StartDate[z];

	            if Decrease_EndDate[x] = . then Decrease_EndDate[z] = Days[i];
	            else Decrease_EndDate[x] = MAX(Decrease_EndDate[z],Days[i]);

	            if Decrease_InitialDose[x] = . then do;
					if Dose[i] NE .A then Decrease_InitialDose[x] = Dose[i];
					else if dose[i] EQ .A AND dose[i-1] NE .A then Decrease_InitialDose[x] = Dose[i-1];
	            	else if dose[i] EQ .A AND dose[i-2] NE .A then Decrease_InitialDose[x] = Dose[i-2];
	            	else if dose[i] EQ .A AND dose[i-3] NE .A then Decrease_InitialDose[x] = Dose[i-3];
				end;
		
	 
			   AnyDecreaseAcrossTotalSequence = "TRUE";
	           NoDecreaseAcrossTotalSequence = "FALSE";
			   FullyConstantAcrossTotalSequence = "FALSE";


				PUTLOG  "Subj_ID: " Subj_ID "Start: " Decrease_StartDate[x]
	                   "END: " Decrease_EndDate[x]
	                    "StartDose: " Decrease_InitialDose[x]
	                    "EndDose: " Decrease_EndDose[x]
	                    "x: " x
						"DoseDecrease[i]: " DoseDecrease[i]
						"DoseDecrease[i+1]: " DoseDecrease[i+1]
						"inIncrease = " inIncrease
						"inINcreaseConstant: " inIncreaseConstant
						"inDecrease = " inDecrease
						"inDecreaseConstant: " inDecreaseConstant
	                    "Decrease RecordType: Intialize StartDate and Dose";
			end;
		end;
		else if DoseConstant[i] = 1 and DoseIncrease[i] = 0 and DoseDecrease[i] = 0 then do;
			if inIncrease = 0 and inDecrease = 0 then CONTINUE;
			if inIncrease = 1 and inDecrease = 0 then do;
				if inIncreaseConstant = 0 then do;
				
					if Dose[i] NE .A then IncreaseConstantStartDose = Dose[i];
					else if dose[i] EQ .A AND dose[i-1] NE .A then IncreaseConstantStartDose = Dose[i-1];
	            	else if dose[i] EQ .A AND dose[i-2] NE .A then IncreaseConstantStartDose = Dose[i-2];
	            	else if dose[i] EQ .A AND dose[i-3] NE .A then IncreaseConstantStartDose = Dose[i-3];

					IncreaseConstantStartDate = days[i];
					
					inIncreaseConstant = 1;

					PUTLOG  "Subj_ID: " Subj_ID "Constant Start Date: "IncreaseConstantStartDate
							"Constant Start Dose: "IncreaseConstantStartDose
							"z: " z
							"DoseIncrease[i]: " DoseIncrease[i]
							"DoseIncrease[i+1]: " DoseIncrease[i+1]
							"inIncrease = " inIncrease
							"inINcreaseConstant: " inIncreaseConstant
							"inDecrease = " inDecrease
							"inDecreaseConstant: " inDecreaseConstant
							"INcrease RecordType: Initalize Constant";

				end;
				else if inIncreaseConstant = 1 then 
				
				PUTLOG  "Subj_ID: " Subj_ID "Constant Start Date: "IncreaseConstantStartDate
						"Constant Start Dose: "IncreaseConstantStartDose
						"z: " z
						"inIncrease = " inIncrease
						"inINcreaseConstant: " inIncreaseConstant
						"inDecrease = " inDecrease
						"inDecreaseConstant: " inDecreaseConstant
						"INcrease RecordType: Current Constant State";

			end;
			else if inDecrease = 1 and inIncrease = 0 then do;
				if inDecreaseConstant = 0 then do;
					
					if Dose[i] NE .A then DecreaseConstantStartDose = Dose[i];
					else if dose[i] EQ .A AND dose[i-1] NE .A then DecreaseConstantStartDose = Dose[i-1];
	            	else if dose[i] EQ .A AND dose[i-2] NE .A then DecreaseConstantStartDose = Dose[i-2];
	            	else if dose[i] EQ .A AND dose[i-3] NE .A then DecreaseConstantStartDose = Dose[i-3];

					DecreaseConstantStartDate = days[i];
				end;
				*else if inDecreaseConstant = 1 then CONTINUE;

				PUTLOG  "Subj_ID: " Subj_ID "Constant Start Date: " DecreaseConstantStartDate
						"Constant Start Dose: " DecreaseConstantStartDose
						"x: " x
						"DoseDecrease[i]: " DoseDecrease[i]
						"DoseDecrease[i+1]: " DoseDecrease[i+1]
						"inIncrease = " inIncrease
						"inDecrease = " inDecrease
						"Decrease RecordType: Initalize Constant";

				end;
				else if inDecreaseConstant = 1 then 

				PUTLOG  "Subj_ID: " Subj_ID "Constant Start Date: " DecreaseConstantStartDate
               			"Constant Start Dose: " DecreaseConstantStartDose
               			"x: " x
						"DoseDecrease[i]: " DoseDecrease[i]
						"DoseDecrease[i+1]: " DoseDecrease[i+1]
						"inIncrease = " inIncrease
						"inINcreaseConstant: " inIncreaseConstant
						"inDecrease = " inDecrease
						"inDecreaseConstant: " inDecreaseConstant
						"Decrease RecordType: Current Constant State";
		end;
		else if DoseIncrease[i] = .D then do;
			if inIncrease = 0 and inDecrease = 0 then CONTINUE;
			else if inIncrease = 1 then do;
				if inIncreaseConstant = 0 then do;
					Increase_EndDate[z] = Days[i-1];
					Increase_EndDose[z] = Dose[i-1];
					inIncreaseConstant = 0;
				end;
				else if inIncreaseConstant = 1 then do;
					Increase_EndDate[z] = IncreaseConstantStartDate;
					Increase_EndDose[z] = IncreaseConstantStartDose;
					inIncreaseConstant = 0;
				end;
	    
				
				inIncrease = 0;
	            PUTLOG  "Subj_ID: " Subj_ID "Start: " Increase_StartDate[z]
	                "END: " Increase_EndDate[z]
	                    "StartDose: " Increase_InitialDose[z]
	                    "EndDose: " Increase_EndDose[z]
	                    "z: " z
						"inIncrease = " inIncrease
						"inINcreaseConstant: " inIncreaseConstant
						"inDecrease = " inDecrease
						"inDecreaseConstant: " inDecreaseConstant
	                    "Increase RecordType: End of the Episode";
	            z + 1;

			end;
			else if inDecrease = 1 then do;
				if inDecreaseConstant = 1 then do;
					Decrease_EndDate[x] = DecreaseConstantStartDate;
					Decrease_EndDose[x] = DecreaseConstantStartDose;
					inDecreaseConstant = 0;
				end;
				else if inDecreaseConstant = 0 then do;
					Decrease_EndDate[x] = Days[i-1];
					Decrease_EndDose[x] = Dose[i-1];
	            end;
				inDecrease = 0;

	            PUTLOG  "Subj_ID: " Subj_ID "Start: " Decrease_StartDate[z]
	                   "END: " Decrease_EndDate[x]
	                    "StartDose: " Decrease_InitialDose[x]
	                    "EndDose: " Decrease_EndDose[x]
	                    "x: " x
						"inIncrease = " inIncrease
						"inINcreaseConstant: " inIncreaseConstant
						"inDecrease = " inDecrease
						"inDecreaseConstant: " inDecreaseConstant
						"DoseDecrease[i]: " DoseDecrease[i]
						"DoseDecrease[i-1]: " DoseDecrease[i-1]
	                    "Decrease RecordType: End of the Episode";
	            x + 1;
			end;
		end;
		/*** At the end of the dosing sequence, we need to terminate the sequence regardless if we are
		inIncrease or inDecrease ****/
		else if i = NumDaysSeqObserved then do;
			if inIncrease = 1 and inDecrease = 0 then do;
			
				if inIncreaseConstant = 1 then do;
					Increase_EndDate[z] = IncreaseConstantStartDate;
					Increase_EndDose[z] = IncreaseConstantStartDose;
					inIncreaseConstant = 0;
				end;
				else if inIncreaseConstant = 0 then do;
					Increase_EndDate[z] = Days[i-1];
					Increase_EndDose[z] = Dose[i-1];
					inIncreaseConstant = 0;
				end;
	            inIncrease = 0;
						PUTLOG  "Subj_ID: " Subj_ID "Start: " Increase_StartDate[z]
	                   "END: " Increase_EndDate[z]
	                    "StartDose: " Increase_InitialDose[z]
	                    "EndDose: " Increase_EndDose[z]
	                    "z: " z
						"inIncrease = " inIncrease
						"inINcreaseConstant: " inIncreaseConstant
						"inDecrease = " inDecrease
						"inDecreaseConstant: " inDecreaseConstant
	                    "Increase RecordType: End of the Dosing Sequence";
	            z + 1;
			end;
			else if inDecrease = 1 and inIncrease = 0 then do;
			
				if inDecreaseConstant = 1 then do;
					Decrease_EndDate[x] = DecreaseConstantStartDate;
					Decrease_EndDose[x] = DecreaseConstantStartDose;
					inDecreaseConstant = 0;
				end;
				else if inDecreaseConstant = 0 then do;
					Decrease_EndDate[x] = Days[i-1];
					Decrease_EndDose[x] = Dose[i-1];
					inDecreaseConstant = 0;
				end;
	            inDecrease = 0;
	                PUTLOG  "Subj_ID: " Subj_ID "Start: " Decrease_StartDate[z]
	                   "END: " Decrease_EndDate[x]
	                    "StartDose: " Decrease_InitialDose[x]
	                    "EndDose: " Decrease_EndDose[x]
	                    "x: " x
						"DoseDecrease[i]: " DoseDecrease[i]
						"DoseDecrease[i-1]: " DoseDecrease[i-1]
						"inIncrease = " inIncrease
						"inINcreaseConstant: " inIncreaseConstant
						"inDecrease = " inDecrease
						"inDecreaseConstant: " inDecreaseConstant
	                    "Decrease RecordType: End of the Dosing Sequence";
	            x + 1;
			end;
		end;
	end;

	/**** Checking for Number of Days for INcreases and Decreases, and calculating rates
	of Increase and Decrease for all subjects *****/
	array Increase_NumDays[50];
	array RatetoRampUp[50];
	array Decrease_NumDays[50];
	array RatetoRampDown[50];

	do i = 1 to dim(Increase_StartDate);
		if Increase_StartDate[i] > 0 then do;
			Increase_NumDays[i] = (Increase_EndDate[i]-Increase_StartDate[i]) + 1;
			RatetoRampUp[i] = (Increase_EndDose[i] - Increase_Initialdose[i])/(Increase_NumDays[i]);
			PUTLOG 	"Subj_ID: " Subj_ID "INCREASE RECORDS: "
					"Z: " i "Increase_StartDate: " Increase_StartDate[i] " Increase_EndDate: " Increase_EndDate[i]
				   "Increase_InitialDose: " Increase_InitialDose[i] " Increase_EndDose: " Increase_EndDose[i]
				   "Increase_NumDays: " Increase_NumDays[i] " RatetoRampUp: " RatetoRampUp[i]; 
		end;
		if Decrease_StartDate[i] > 0 then do;
			Decrease_NumDays[i] = (Decrease_EndDate[i] - Decrease_StartDate[i]) + 1;
			RatetoRampDown[i] = (Decrease_EndDose[i] - Decrease_Initialdose[i])/(Decrease_NumDays[i]);
			PUTLOG "Subj_ID: " Subj_ID "DECREASE RECORDS: "
					"Z: " i "Decrease_StartDate: " Decrease_StartDate[i] " Decrease_EndDate: " Decrease_EndDate[i]
				   "Decrease_InitialDose: " Decrease_InitialDose[i] " Decrease_EndDose: " Decrease_EndDose[i]
				   "Decrease_NumDays: " Decrease_NumDays[i] " RatetoRampDown: " RatetoRampDown[i]; 

		end;
	end;




    /*
    if AnyTaper = 1 and AnyIncrease = 1 then AnyBoth = 1;
    else if AnyTaper = .N and AnyIncrease = .N then AnyBoth = .N;
    else AnyBoth = 0;

    if PostTaper = 1 and PostIncrease = 1 then PostBoth = 1;/
    else if PostTaper = .N and PostIncrease = .N then PostBoth = .N;
    else PostBoth = 0;
    */
    if Min_Dosage = Max_Dosage then ChangeAll = "No Change";
    else if Min_Dosage NE Max_Dosage then ChangeAll = "Changed";

    if MinDose_PostInterview = MaxDose_PostInterview then ChangePost = "No Change";
    else if MinDose_PostInterview NE MaxDose_PostInterview then ChangePost = "Changed";


    /*

    PJA 5/31/2019 - this code is now redudant as it has been asked in the previous do loop when
    looking at increase and taper start and end dates. As a result, this code is no longer needed

    Observe Tapers and Increases

    if Min_Dosage NE Max_dosage then do;
        do i = 1 by 1 to (daysobs_alldose - 1);
            if (dose[i] > dose[i+1]) OR (AnyTaper = 1) then do;
                AnyTaper = 1;
                NoTaper = 0;
            end;
            else do;
                AnyTaper = 0;
                NoTaper = 1;
            end;

            if (dose[i] < dose[i+1]) OR (AnyIncrease = 1) then do;
                AnyIncrease = 1;
                NoIncrease = 0;
            end;
            else do;
                AnyIncrease = 0;
                NoIncrease = 1;
            end;
        end;
    end;
    if (MaxPostInterview NE MinPostInterview) AND NumDays_PostSurvey > 5 then do;
        do i = 1 by 1 to (NumDays_PostSurvey - 2);
            if (post_dose[i] > post_dose[i+1]) OR (PostTaper = 1) then do;
                PostTaper = 1;
                PostNoTaper = 0;
            end;
            else do;
                PostTaper = 0;
                PostNoTaper = 1;
            end;

            if (post_dose[i] < post_dose[i+1]) OR (PostIncrease = 1) then do;
                PostIncrease = 1;
                PostNoIncrease = 0;
            end;
            else do;
                PostIncrease = 0;
                PostNoIncrease = 1;
            end;
        end;
    end;
    if Min_Dosage EQ Max_dosage then do;
        AnyTaper = .N;
        NoTaper = .N;
        AnyIncrease = .N;
        NoIncrease = .N;
    end;
    if MaxPostInterview = MinPostInterview then do;
        PostIncrease = .N;
        PostNoIncrease = .N;
        PostTaper = .N;
        PostNoTaper = .N;
    end;
    **************/


    /************* NEW ANALYSIS TO ACCOUNT FOR Discharges ***************/

    if Current = "FALSE" then do;
        /********** Breaking the subjects into multiple groups ***********/
        if SumEpisodes = 1 then NumEpisodesatDischarge = "1 Discharge";
        else if SumEpisodes > 1 then NumEpisodesatDischarge = "More than 1 Discharge";

        FinalDose = dose[NumDaysSeqObserved];

        if NumDaysDoseObserved > 30 then NumDaysDoseObserved_Dichot = "More than 30 Days of Dosing";
        if NumDaysDoseObserved < 30 then NumDaysDoseObserved_Dichot = "Less than 30 Days of Dosing";

        if NumDaysDoseObserved > 30 then do;
            Day30SeqObserved = NumDaysSeqObserved - 30;
            do i = Day30SeqObserved by 1 to NumDaysSeqObserved;
                if (dose[i] > dose[i+1]) OR (TerminalTaper = 1) then do;
                    TerminalTaper = 1;
                    TerminalNoTaper = 0;
                end;
                else do;
                    TerminalTaper = 0;
                    TerminalNoTaper = 1;
                end;

                if (dose[i] < dose[i+1]) OR (TerminalIncrease = 1) then do;
                    TerminalIncrease = 1;
                    TerminalNoIncrease = 0;
                end;
                else do;
                    TerminalIncrease = 0;
                    TerminalNoIncrease = 1;
                end;
            end;
        end;
        else PUTLOG Subj_ID " has less then 30 days of data prior to discharge - excluding accordingly from Taper/Increase analysis";

        if TerminalNoIncrease = 1 and TerminalNoTaper = 1 then DoseStatusDischarge = "Constant";
        else if TerminalTaper  = 1 and TerminalIncrease = 0 then DoseStatusDischarge = "Detox";
        else if TerminalIncrease = 1 and TerminalTaper = 0 then DoseStatusDischarge = "Increase";
        else if TerminalTaper = . and TerminalIncrease = . then DoseStatusDischarge = "Excluded";
        else if TerminalTaper = 1 and TerminalIncrease = 1 then DoseStatusDischarge = "Both Increase/Detox";

        if DoseStatusDischarge IN ("Constant","Increase") then DoseStatusDischarge_dichotomous = "Constant/Increase";
        else if DoseStatusDischarge = "Detox" then  DoseStatusDischarge_dichotomous = "Detox";
    end;

    Label FinalDate = "The Last Possible Date in the Sequence"
        NumDaysSinceExtract = "The Number of Days Since Extract for all patients to last dosing record for discharged patients"
        NumDaysToday = "The Number of Days Since Extract to Today for ALL Patients"
        NumDaysTx = "Number of Days in which subject is in treatment"
        NumDaysSinceExtract = "If Discharged, number of days from discharge to date of extract"
        NumDaysToday = "If Discharged, number of days from Discharge to today 4/12/19"
        daysobs_alldose = "The Number of Days by which someone has received a Methadone Dose"
        min_dosage = "The ABSOLUTE minimum dose that a subject received"
        max_dosage = "The ABSOLUTE maxmimum dose that a subject received"
        ReceivedOtherthanMethadone = "Has the subject EVER received a treatment drug other than  Methadone?"
        NumDaysSeqObserved = "The Number of Days (including "
        ReceivedMethadone = "Has the subject EVER received Methadone"
        Min_StartDate "The Start Date of the ABSOLUTE minimum dose that a subject received"
        Min_EndDate = "The End Date of the ABSOLUTE minimum dose that a subject received"
        NumDays_MinDose = "The Number of Days at the ABSOLUTE minimum dose"
        Max_StartDate = "The Start Date of the ABSOLUTE Maximum Dose"
        Max_EndDate = "The End Date of the ABSOLUTE Maximum Dose"
        NumDays_MaxDose = "The Number of Days at the ABSOLUTE MAXIMUM dose"
        Dose_Interview = "The Dose on the Day of Interview"
        Date_Study_Initiation = "Temporary variable as to acertain when subject has entered the study or has been interviewed"
        MinStartDate_PostInterview = "Start Date of the Minimum Dose Post Interview"
        MinEndDate_PostInterview = "End Date of the Minimum Dose Post Interview"
        MinDose_PostInterview = "Minimum Dose Subject Received Post-Interview"
        MaxDose_PostInterview = "Maximum Dose Subject Received Post-Interview";


    drop i _TEMPORARY_ post_dose1-post_dose5000 post_days1-post_days5000 p1-p4000 THB1-THB4000;
run;

proc printto;
run;

ods html file = "Proc Means AND PROC PRINTS.html";

proc means data = METHADOS.all_analysis N NMISS MEAN MIN MEDIAN MAX RANGE;
	var RatetoRampUp1-RatetoRampUp15
		RatetoRampDown1-RatetoRampDown15;
run;


proc print data = METHADOS.all_analysis;
	var Subj_ID Decrease_NumDays1-Decrease_NumDays50 RatetoRampDown1-RatetoRampDown50;
run;

ods html close;

TITLE;
ods html file = "Troublesome Records.html";

/*TITLE "RatetoRampUp1 < 0";
proc print data = METHADOS.all_analysis (WHERE = (z <= 2 AND Z >1));
var Subj_ID;
run;*/
/************ Ramp UP Proc Prints **************************/
TITLE "RatetoRampUp1 < 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp1 < 0 and RatetoRampUp1 NE .));
var Subj_ID;
run;

TITLE "RatetoRampUp1 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp1 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampUp1 = . and they Only have 1 RATE TO RAMPUP";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp1 EQ . AND z > 2));
var Subj_ID;
run;

TITLE "RatetoRampUp2 < 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp2 < 0 and RatetoRampUp2 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampUp2 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp2 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampUp3 < 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp3 < 0 and RatetoRampUp3 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampUp3 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp3 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampUp4 < 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp4 < 0 and RatetoRampUp4 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampUp4 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp4 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampUp5 < 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp5 < 0 and RatetoRampUp5 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampUp5 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp5 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampUp6 < 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp6 < 0 and RatetoRampUp6 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampUp6 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp6 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampUp7 < 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp7 < 0 and RatetoRampUp7 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampUp7 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp7 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampUp8 < 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp8 < 0 and RatetoRampUp8 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampUp8 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp8 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampUp9 < 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp9 < 0 and RatetoRampUp9 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampUp9 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp9 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampUp10 < 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp10 < 0 and RatetoRampUp10 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampUp10 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampUp10 = 0));
	var Subj_ID;
run;

/*************************** Rate to Ramp Down *************************/
TITLE "RatetoRampDown1 > 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown1 > 0 and RatetoRampDown1 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampDown1 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown1 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampDown2 > 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown2 > 0 and RatetoRampDown2 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampDown2 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown2 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampDown3 > 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown3 > 0 and RatetoRampDown3 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampDown3 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown3 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampDown4 > 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown4 > 0 and RatetoRampDown4 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampDown4 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown4 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampDown5 > 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown5 > 0 and RatetoRampDown5 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampDown5 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown5 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampDown6 > 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown6 > 0 and RatetoRampDown6 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampDown6 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown6 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampDown7 > 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown7 > 0 and RatetoRampDown7 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampDown7 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown7 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampDown8 > 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown8 > 0 and RatetoRampDown8 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampDown8 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown8 = 0));
	var Subj_ID;
run;

TITLE "RatetoRampDown9 > 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown9 > 0 and RatetoRampDown9 NE .));
	var Subj_ID;
run;

TITLE "RatetoRampDown9 = 0";
proc print data = METHADOS.all_analysis (WHERE = (RatetoRampDown9 = 0));
	var Subj_ID;
run;
ods html close;

