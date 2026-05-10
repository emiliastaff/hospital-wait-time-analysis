--Create table schema to import data
DROP TABLE IF EXISTS ER_wait_time;
CREATE TABLE ER_wait_time (
	visit_ID VARCHAR(50),
	patient_ID VARCHAR (25),
	hospital_ID	VARCHAR (20),
	hospital_Name VARCHAR (75),
	region VARCHAR (15),
	visit_date DATE,
	dow VARCHAR(10),
	season VARCHAR (10),
	time_day VARCHAR (25),
	urgency_level VARCHAR (15),
	nurse_patient_ratio INT,
	specialist_availability INT,
	facility_size_beds INT,
	time_to_registration_min INT,
	time_to_triage_min INT,
	time_to_medical_professional INT,
	total_wait_time INT,
	patient_outcome	VARCHAR (25),
	patient_satisfaction INT
);

-- Fixing import issue:
-- CSV contains TIMESTAMP values while the column was originally defined as DATE
ALTER TABLE ER_wait_time
ALTER COLUMN visit_date TYPE TIMESTAMP;

--Viewing table to verify correct data import
SELECT *
FROM er_wait_time
LIMIT 50;

--Identifying NULL values for key columns
SELECT 
	COUNT(*) AS total_count, 
    COUNT(*) FILTER (WHERE visit_id IS NULL) AS null_visit_id,
    COUNT(*) FILTER (WHERE patient_id IS NULL) AS null_patient_id,
    COUNT(*) FILTER (WHERE hospital_id IS NULL) AS null_hospital_id,
    COUNT(*) FILTER (WHERE visit_date IS NULL) AS null_visit_date,
    COUNT(*) FILTER (WHERE total_wait_time IS NULL) AS null_total_wait_time,
    COUNT(*) FILTER (WHERE patient_satisfaction IS NULL) AS null_patient_satisfaction
FROM er_wait_time;
--Results confirm there are no NULL values in key analytical columns.
--Check for duplicates within unique identifier 
SELECT 
	visit_id,
	COUNT(*)
FROM er_wait_time
GROUP BY visit_id
HAVING COUNT(*) > 1;

--Check for impossible wait times
SELECT 
	total_wait_time
FROM er_wait_time
WHERE total_wait_time <0;

--Check for consistency in urgency level categories: Critical, High, Medium, Low 
SELECT 
	DISTINCT urgency_level
FROM er_wait_time;

--KEY BUSINESS QUESTIONS 

-- 1. Which 3 hospitals have the highest average wait times?

SELECT 
	hospital_id, 
	hospital_name,
	ROUND(AVG(total_wait_time),2) AS avg_wait_time_min
FROM er_wait_time
GROUP BY hospital_id, hospital_name
ORDER BY avg_wait_time_min DESC
LIMIT 3;

-- *HOSP-1, HOSP-1, HOSP-2*

-- 2. Which time periods experience the greatest congestion?
-- Ordering primarily by average wait time to identify periods with greatest operational delay.

	--2A. Congestion by time of day
SELECT 
	time_day, 
	ROUND(AVG(total_wait_time),2) AS avg_wait_time_min, 
	COUNT(*) AS total_visits, ROUND((COUNT(*) * 100.0)/SUM(COUNT(*)) OVER(), 2) AS percentage_visits
FROM er_wait_time
GROUP BY time_day
ORDER BY avg_wait_time_min DESC, total_visits DESC;

--Results show evening periods experience both elevated patient volumes (34.50% of total visits) and longer average wait times, suggesting increased operational congestion during these hours.

	--2B Congestion by the day of week 
SELECT
	dow, 
	ROUND(AVG(total_wait_time),2) AS avg_wait_time_min, 
	COUNT(*) AS total_visits, 
	ROUND((COUNT(*) * 100.0)/SUM(COUNT(*)) OVER(), 2) AS percentage_visits
FROM er_wait_time
GROUP BY dow
ORDER BY avg_wait_time_min DESC, total_visits DESC;
--Mondays experienced the highest patient volume (15.36% of total visits) alongside the longest average wait times, indicating peak demand pressure at the beginning of the week.
--Friday has the second-highest average wait time despite having the second lowest patient volume (13.70%), suggesting possible operational inefficiencies or staffing constraints.

	--2C Congestion by season 
SELECT
	season, 
	ROUND(AVG(total_wait_time),2) AS avg_wait_time_min, 
	COUNT(*) AS total_visits,
	ROUND((COUNT(*) * 100.0)/SUM(COUNT(*)) OVER(), 2) AS percentage_visits
FROM er_wait_time
GROUP BY season
ORDER BY avg_wait_time_min DESC, total_visits DESC;
--Winter recorded the highest average wait times despite Summer having a slightly greater patient volume (25.62% of total visits were in Summer, compared to 25.16% in Winter), suggesting seasonal operational challenges beyond demand alone.

-- 3. Do staffing levels reduce wait time?
SELECT 
	nurse_patient_ratio,
	ROUND(AVG(total_wait_time),2) AS avg_wait_time
FROM er_wait_time 
GROUP BY nurse_patient_ratio
ORDER BY nurse_patient_ratio;
--Results indicate a strong inverse relationship between nurse-to-patient ratios and average wait times, with higher staffing levels associated with significantly shorter patient waits.

-- 4. Does urgency level impact wait time appropriately? 
SELECT 
	urgency_level, 
	ROUND(AVG(total_wait_time),2) AS avg_wait_time,
	COUNT(*) AS total_visits
FROM er_wait_time
GROUP BY urgency_level
ORDER BY avg_wait_time DESC;
--The results show the average wait time decreases as the urgency level increases, which is the expected operational procedure. However, there is an approx 80 min difference between the average wait time of medium and low level urgencies, which may indicate low-urgency patients are being over-delayed.

-- 5. At what point does patient satisfaction decline?
--We will be using wait time to analyse patient satisfaction
WITH patient_wait_time AS(
SELECT 
	patient_satisfaction,
	CASE WHEN total_wait_time < 30 THEN 'short wait'
		WHEN total_wait_time < 60 THEN 'moderate wait'
		ELSE 'long wait'
		END AS wait_length
FROM er_wait_time)
SELECT 
	ROUND(AVG(patient_satisfaction),2) AS avg_patient_satisfaction,
	wait_length,
	COUNT(*) AS total_patients
FROM patient_wait_time
GROUP BY wait_length;
--The results highlight a direct link between patient satisfaction and wait time, whereby a longer wait time decreases patient satisfaction. 

-- 6. Which stage of the patient's journey creates the biggest bottleneck?	
--We've identified that a longer total wait time decreases patient satisfaction. The next step is to identify which stage of the patient journey contributes most to total wait time.

SELECT
	ROUND(AVG(total_wait_time), 2) AS avg_wait_time,
	ROUND(AVG(time_to_registration_min),2) AS registration_time,
	ROUND(AVG(time_to_registration_min) * 100.0/ AVG(total_wait_time), 2) AS registration_time_pct,
	ROUND(AVG(time_to_triage_min),2) AS triage_time, 
	ROUND(AVG(time_to_triage_min) * 100.0/ AVG(total_wait_time), 2) AS triage_time_pct,
	ROUND(AVG(time_to_medical_professional),2) AS medical_prof_time,
	ROUND(AVG(time_to_medical_professional) * 100.0/ AVG(total_wait_time), 2) AS medical_prof_pct 
FROM er_wait_time;
--Time spent waiting to see a medical professional accounted for over 55% of the average patient wait time, identifying physician availability as the primary operational bottleneck.

-- 7. Do longer wait times increase the likelihood of patients leaving without being seen?
SELECT
	patient_outcome,
	AVG(total_wait_time) AS avg_wait_time,
	COUNT(*) AS total_patients
FROM er_wait_time
GROUP BY patient_outcome;
--Patients who left without being seen experienced substantially longer average wait times compared to admitted or discharged patients, suggesting excessive delays may contribute to patient abandonment.
--Extra info to identify what % of paitents leave without being seen.
SELECT
    patient_outcome,
    COUNT(*) AS total_patients,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    ) AS pct_patients,
    ROUND(AVG(total_wait_time), 2) AS avg_wait_time
FROM er_wait_time
GROUP BY patient_outcome;

--Although only approximately 5% of patients left without being seen, this still represents a significant operational concern given the substantially longer wait times experienced by these patients.

-- *OVERALL PROJECT SUMMARY*
-- Key findings from the analysis include:

-- 1. Evening periods and Mondays experienced the greatest operational congestion,
--  with both elevated patient volumes and longer average wait times.

-- 2. Higher nurse-to-patient ratios were strongly associated with reduced wait times,
--    suggesting staffing levels play a significant role in operational efficiency.

-- 3. Lower urgency patients experienced disproportionately longer delays,
--    indicating potential inefficiencies in patient flow prioritisation.

-- 4. Patient satisfaction declined significantly as wait times increased,
--    highlighting the operational impact on patient experience.

-- 5. Waiting to see a medical professional accounted for the majority of total wait time,
--    identifying physician availability as the primary bottleneck.

-- 6. Patients who left without being seen experienced substantially longer average wait times,
--    suggesting excessive delays may contribute to patient abandonment.