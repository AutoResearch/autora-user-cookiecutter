// To use the jsPsych package first install jspsych using `npm install jspsych`
// This example uses the rdk plugin. Install it via `npm install @jspsych-contrib/plugin-rdk`
// This example uses the html-keyboard-response plugin. Install it via `npm install @jspsych/plugin-html-keyboard-response`
// Here is documentation on how to program a jspsych experiment using npm:
// https://www.jspsych.org/7.3/tutorials/hello-world/#option-3-using-npm

import {initJsPsych} from 'jspsych';
import 'jspsych/css/jspsych.css'
import jsPsychRdk from '@jspsych-contrib/plugin-rdk';
import htmlKeyboardResponse from '@jspsych/plugin-html-keyboard-response';

/**
 * This is the main function where you program your experiment. Install jsPsych via node and
 * use functions from there
 * @param id this is a number between 0 and number of participants. You can use it for example to counterbalance between subjects
 * @param condition this is a condition (4-32. Here we want to find out how the training length impacts the accuracy in a testing phase)
 * @returns {Promise<*>} the accuracy in the post-trainging phase relative to the pre-training phase
 */
const main = async (id, condition) => {
    const jsPsych = initJsPsych()

    // constants
    const FIXATION_DURATION = 800
    const SOA_DURATION = 400
    const STIMULUS_DURATION = 2000
    const FEEDBACK_DURATION = 800
    const NUMBER_OF_TRIALS = 10

    // key to response mapping 0 degree -> f, 180 degree -> j
    const responseToKeyMapping = {
        0: 'j',
        180: 'f',
    }


    // For convenience, we first define a function that returns a trial
    // (as sequence of fixation, soa, stimulus and feedback)
    const trial = (direction, coherence) => {
        const stimulus_timeline = []
        // FIXATION
        stimulus_timeline.push(
            {
                type: htmlKeyboardResponse,
                stimulus: "+",
                trial_duration: FIXATION_DURATION
            })

        // SOA
        stimulus_timeline.push({
            type: htmlKeyboardResponse,
            stimulus: "",
            trial_duration: SOA_DURATION,
        })

        // STIMULUS
        stimulus_timeline.push({
            type: jsPsychRdk,
            correct_choice: () => {
                return [responseToKeyMapping[direction]]
            },
            move_distance: 3,
            coherence: coherence,
            coherent_direction: direction,
            choices: [responseToKeyMapping[0], responseToKeyMapping[180]],
            trial_duration: STIMULUS_DURATION,
        })

        // FEEDBACK
        stimulus_timeline.push({
            type: htmlKeyboardResponse,
            stimulus: () => { // stimulus depends on last correct
                const correct = jsPsych.data.getLastTrialData()['trials'][0]['correct']
                if (correct) {
                    return 'CORRECT'
                }
                return 'FALSE'
            },
            trial_duration: FEEDBACK_DURATION
        })
        return stimulus_timeline

    }

    // Here we set up functions to randomly select a direction

    // create lists for colors and words
    const directions = [0, 180]

    // get a random direction from the list
    const rand_direction = () => {
        return directions[Math.floor(Math.random() * directions.length)];
    }


    // MAKE THE EXPERIMENT TIMELINE

    // Instructions
    let instructions = [
        {
            type: htmlKeyboardResponse,
            stimulus: 'In the following experiment you are asked to name the movement direction of dots<br>Press >> Space << to continue',
            choices: [' ']
        }
    ]

    instructions.push({
        type: htmlKeyboardResponse,
        stimulus: `If most of the dots move to the left, press >> ${responseToKeyMapping[180]} << <br>Press >> ${responseToKeyMapping[180]} >> to continue`,
        choices: [responseToKeyMapping[180]]
    })

    instructions.push({
        type: htmlKeyboardResponse,
        stimulus: `If most of the dots move to the right, press >> ${responseToKeyMapping[0]} << <br>Press >> ${responseToKeyMapping[0]} >> to continue`,
        choices: [responseToKeyMapping[0]]
    })


    instructions.push(
        {
            type: htmlKeyboardResponse,
            stimulus: 'The experiment will start now<br>Press >> Space << to continue',
            choices: [' ']
        }
    )


    // Here, we use the condition to set the coherence of a trial
    let trials = []
    for (let i = 0; i < NUMBER_OF_TRIALS; i++) {
        trials = trials.concat(trial(rand_direction(), condition['coherence']));
    }


    // this is the timeline: instructions, pretraining, pause, training, pause, posstraining
    const timeline = [...instructions, ...trials]

    // run the experiment and wait it to finish
    await jsPsych.run(timeline)

    // calculate accuracy (this will be our observation)
    const accuracy = jsPsych.data.get().filter({
        'trial_type': 'rdk',
        'correct': true
    }).count() / NUMBER_OF_TRIALS


    // Here, we also return the condition that belongs to the accuracy.
    // It is best practice to return the full experiment data!
    return JSON.stringify({condition, accuracy: accuracy})
}


export default main