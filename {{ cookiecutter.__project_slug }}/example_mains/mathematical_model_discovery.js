// To use the jsPsych package first install jspsych using `npm install jspsych`
// This example uses the rdk plugin. Install it via `npm install @jspsych-contrib/plugin-rdk`
// This example uses the html-keyboard-response plugin. Install it via `npm install @jspsych/plugin-html-keyboard-response`
// Here is documentation on how to program a jspsych experiment using npm:
// https://www.jspsych.org/7.3/tutorials/hello-world/#option-3-using-npm

import {initJsPsych} from 'jspsych';
import 'jspsych/css/jspsych.css'
import jsPsychRok from '@jspsych-contrib/plugin-rok';
import htmlKeyboardResponse from '@jspsych/plugin-html-keyboard-response';

/**
 * This is the main function where you program your experiment. Install jsPsych via node and
 * use functions from there
 * @param id this is a number between 0 and number of participants. You can use it for example to counterbalance between subjects
 * @param condition this is a condition (4-32. Here we want to find out how the training length impacts the accuracy in a testing phase)
 * @returns {Promise<*>} the accuracy in the post-trainging phase relative to the pre-training phase
 */
const main = async (id, condition) => {
    const condition_parsed = JSON.parse(condition)

    const jsPsych = initJsPsych()


    // constants
    const FIXATION_DURATION = 300
    const SOA_DURATION = 100
    const STIMULUS_DURATION = 2000
    const FEEDBACK_DURATION = 300

    // key to response mapping 0 degree -> f, 180 degree -> j
    const responseToKeyMapping = {
        0: 'j',
        180: 'f',
    }

    const block = (sequence) => {
        return {
            timeline: [
                {
                    type: htmlKeyboardResponse,
                    stimulus: '+',
                    choices: "NO_KEYS",
                    trial_duration: FIXATION_DURATION,
                    response_ends_trial: false
                },
                {
                    type: htmlKeyboardResponse,
                    stimulus: '',
                    choices: "NO_KEYS",
                    trial_duration: SOA_DURATION,
                    response_ends_trial: false
                }, {
                    type: jsPsychRok,
                    correct_choice: () => {
                        return [responseToKeyMapping[jsPsych.timelineVariable('direction_orientation')]]
                    },
                    movement_speed: 20,
                    coherent_movement_direction: jsPsych.timelineVariable('direction_movement'),
                    coherent_orientation: jsPsych.timelineVariable('direction_orientation'),
                    coherence_movement: () => {return jsPsych.timelineVariable('coherence_movement')* 100.},
                    coherence_orientation: () => {return jsPsych.timelineVariable('coherence_orientation')* 100.},
                    choices: [responseToKeyMapping[0], responseToKeyMapping[180]],
                    trial_duration: STIMULUS_DURATION,
                },
                {
                    type: htmlKeyboardResponse,
                    stimulus: () => { // stimulus depends on last correct
                        const correct = jsPsych.data.getLastTrialData()['trials'][0]['correct']
                        if (correct) {
                            return 'CORRECT'
                        }
                        return 'FALSE'
                    },
                    trial_duration: FEEDBACK_DURATION,
                    response_ends_trial: false
                }

            ],
            timeline_variables: sequence
        }
    }


    // MAKE THE EXPERIMENT TIMELINE
    let timeline = []

    // Informed Consent
    timeline.push({
        type: htmlKeyboardResponse,
        stimulus: '!!! REPLACE THIS WITH AN CONSENT FORM !!!<br>Press >> Space << to start',
        choices: [' ']
    })

    // Instructions
    timeline.push({
            type: htmlKeyboardResponse,
            stimulus: 'In the following experiment you are asked to name the orientation of triangles<br>Press >> Space << to continue',
            choices: [' ']
        })

    timeline.push({
        type: htmlKeyboardResponse,
        stimulus: `If most of the triangles face to the left, press >> ${responseToKeyMapping[180]} << <br>Press >> ${responseToKeyMapping[180]} << to continue`,
        choices: [responseToKeyMapping[180]]
    })

    timeline.push({
        type: htmlKeyboardResponse,
        stimulus: `If most of the triangles face to the right, press >> ${responseToKeyMapping[0]} << <br>Press >> ${responseToKeyMapping[0]} << to continue`,
        choices: [responseToKeyMapping[0]]
    })

    timeline.push(
        {
            type: htmlKeyboardResponse,
            stimulus: 'The experiment will start now<br>Press >> Space << to continue',
            choices: [' ']
        }
    )

    // The condition is a list of blocks
    for (let i=0; i < condition_parsed.length; i++) {
        timeline.push(block(condition_parsed[i]))
        if (i < condition_parsed.length-1) {
            timeline.push(
                {
                    type: htmlKeyboardResponse,
                    stimulus: 'You can have a small break.<br>The next block will start when you press >> Space << to continue',
                    choices: [' ']
                }
            )
        }
    }

    // run the experiment and wait it to finish
    await jsPsych.run(timeline)

    // return difference between before and after training as observation
    return JSON.stringify(jsPsych.data.get())
}


export default main