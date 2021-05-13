-- This computes the average of lab values that are used in the computation of sofa score, for each stay_id of a subject.
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
SELECT 
s1.subject_id
, stay_id
, AVG(pao2fio2ratio_novent) as pao2fio2ratio_novent_avg
, AVG(pao2fio2ratio_vent) as pao2fio2ratio_vent_avg
, AVG(rate_dobutamine) as rate_dobutamine_avg
, AVG(rate_epinephrine) as rate_epinephrine_avg
, AVG(rate_norepinephrine) as rate_norepinephrine_avg
, AVG(rate_dopamine) as rate_dopamine_avg
, AVG(meanbp_min) as meanbp_min_avg
, AVG(gcs_min) as gcs_min_avg
, AVG(uo_24hr) as uo_24hr_avg
, AVG(bilirubin_max) as bilirubin_max_avg
, AVG(creatinine_max) as creatinine_max_avg
, AVG(platelet_min) as platelet_min_avg
FROM s1 inner join `physionet-data.mimic_core.admissions`as patient on s1.subject_id = patient.subject_id
GROUP BY stay_id, s1.subject_id
