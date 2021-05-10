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
, rn_sus
, patient.deathtime as death_time
, patient.hospital_expire_flag as death_flag
FROM s1 inner join `physionet-data.mimic_core.admissions`as patient on s1.subject_id = patient.subject_id)
SELECT * FROM s2 ORDER BY rn_sus
