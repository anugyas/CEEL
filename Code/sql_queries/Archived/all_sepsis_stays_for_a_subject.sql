-- Creates a table with "onset" time of Sepsis-3 in the ICU.
-- That is, the earliest time at which a patient had SOFA >= 2 and suspicion of infection.
-- As many variables used in SOFA are only collected in the ICU, this query can only
-- define sepsis-3 onset within the ICU.

-- extract rows with SOFA >= 2
-- implicitly this assumes baseline SOFA was 0 before ICU admission.
WITH sofa AS
(
  SELECT stay_id
    , starttime, endtime
    , respiration_24hours as respiration
    , coagulation_24hours as coagulation
    , liver_24hours as liver
    , cardiovascular_24hours as cardiovascular
    , cns_24hours as cns
    , renal_24hours as renal
    , sofa_24hours as sofa_score
    , pao2fio2ratio_novent
    , pao2fio2ratio_vent
    , rate_dobutamine
    , rate_epinephrine
    , rate_norepinephrine
    , rate_dopamine
    , meanbp_min
    , gcs_min
    , uo_24hr
    , bilirubin_max
    , creatinine_max
    , platelet_min
  FROM `physionet-data.mimic_derived.sofa`
  WHERE sofa_24hours >= 2
)
, s1 as
(
  SELECT 
    soi.subject_id
    , soi.stay_id
    -- suspicion columns
    , soi.ab_id
    , soi.antibiotic
    , soi.antibiotic_time
    , soi.culture_time
    , soi.suspected_infection
    , soi.suspected_infection_time
    , soi.specimen
    , soi.positive_culture
    -- sofa columns
    , starttime, endtime
    , respiration, coagulation, liver, cardiovascular, cns, renal
    , sofa_score
    , pao2fio2ratio_novent
    , pao2fio2ratio_vent
    , rate_dobutamine
    , rate_epinephrine
    , rate_norepinephrine
    , rate_dopamine
    , meanbp_min
    , gcs_min
    , uo_24hr
    , bilirubin_max
    , creatinine_max
    , platelet_min
    -- All rows have an associated suspicion of infection event
    -- Therefore, Sepsis-3 is defined as SOFA >= 2.
    -- Implicitly, the baseline SOFA score is assumed to be zero, as we do not know
    -- if the patient has preexisting (acute or chronic) organ dysfunction 
    -- before the onset of infection.
    , sofa_score >= 2 and suspected_infection = 1 as sepsis3
    -- subselect to the earliest suspicion/antibiotic/SOFA row
    , ROW_NUMBER() OVER
    (
        PARTITION BY soi.stay_id
        ORDER BY suspected_infection_time, antibiotic_time, culture_time, endtime
    ) AS rn_sus
  FROM `physionet-data.mimic_derived.suspicion_of_infection` as soi
  INNER JOIN sofa
    ON soi.stay_id = sofa.stay_id 
    AND sofa.endtime >= DATETIME_SUB(soi.suspected_infection_time, INTERVAL 48 HOUR)
    AND sofa.endtime <= DATETIME_ADD(soi.suspected_infection_time, INTERVAL 24 HOUR)
  -- only include in-ICU rows
  WHERE soi.stay_id is not null
)
, s2 as
(SELECT 
s1.subject_id, stay_id
-- note: there may be more than one antibiotic given at this time
, antibiotic_time
-- culture times may be dates, rather than times
, culture_time
, suspected_infection_time
-- endtime is latest time at which the SOFA score is valid
, endtime as sofa_time
, pao2fio2ratio_novent
, pao2fio2ratio_vent
, rate_dobutamine
, rate_epinephrine
, rate_norepinephrine
, rate_dopamine
, meanbp_min
, gcs_min
, uo_24hr
, bilirubin_max
, creatinine_max
, platelet_min
, sofa_score
, respiration, coagulation, liver, cardiovascular, cns, renal
, sepsis3
, patient.deathtime as death_time
, patient.hospital_expire_flag as death_flag
FROM s1 inner join `physionet-data.mimic_core.admissions`as patient on s1.subject_id = patient.subject_id
WHERE rn_sus = 1)
, s3 as
(SELECT s2.subject_id, s2.stay_id
-- note: there may be more than one antibiotic given at this time
, antibiotic_time
-- culture times may be dates, rather than times
, culture_time
, suspected_infection_time
-- endtime is latest time at which the SOFA score is valid
, sofa_time
, pao2fio2ratio_novent
, pao2fio2ratio_vent
, rate_dobutamine
, rate_epinephrine
, rate_norepinephrine
, rate_dopamine
, meanbp_min
, gcs_min
, uo_24hr
, bilirubin_max
, creatinine_max
, platelet_min
, sofa_score
, respiration, coagulation, liver, cardiovascular, cns, renal
, sepsis3
, death_time
, death_flag
, patient_vitals.heart_rate
, patient_vitals.sbp
, patient_vitals.mbp
, patient_vitals.dbp
, patient_vitals.sbp_ni
, patient_vitals.mbp_ni
, patient_vitals.dbp_ni
, patient_vitals.temperature
, patient_vitals.glucose
, patient_vitals.spo2
, patient_vitals.resp_rate
, patient_vitals.charttime 
, ROW_NUMBER() OVER
    (
        PARTITION BY patient_vitals.stay_id
        ORDER BY patient_vitals.charttime desc
    ) AS rn_charttime
 FROM s2 left join `physionet-data.mimic_derived.vitalsign` as patient_vitals on s2.subject_id = patient_vitals.subject_id and s2.stay_id = patient_vitals.stay_id and patient_vitals.charttime <= s2.sofa_time )
, s4 as
(SELECT *
, ROW_NUMBER() OVER 
(
  PARTITION BY subject_id
  ORDER BY sofa_time desc
) AS rn_sofa_stay 
FROM s3 WHERE rn_charttime = 1)
, s5 as
(SELECT * FROM s4)
, s6 as
(SELECT ie.subject_id, ie.hadm_id, ie.stay_id
-- patient level factors
, pat.gender
-- hospital level factors
, adm.admittime, adm.dischtime
, DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) as los_hospital
, DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age as admission_age
, DENSE_RANK() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS hospstay_seq
, CASE
    WHEN DENSE_RANK() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) = 1 THEN True
    ELSE False END AS first_hosp_stay

-- icu level factors
, ROUND(DATETIME_DIFF(ie.outtime, ie.intime, HOUR)/24.0, 2) as ICULOS
, DENSE_RANK() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) AS icustay_seq

-- first ICU stay for the current hospitalization
, CASE
    WHEN DENSE_RANK() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) = 1 THEN True
    ELSE False END AS first_icu_stay

FROM physionet-data.mimic_icu.icustays ie
INNER JOIN physionet-data.mimic_core.admissions adm
    ON ie.hadm_id = adm.hadm_id
INNER JOIN physionet-data.mimic_core.patients pat
    ON ie.subject_id = pat.subject_id
)
SELECT * FROM s5 left join s6 on s5.subject_id = s6.subject_id and s5.stay_id = s6.stay_id
