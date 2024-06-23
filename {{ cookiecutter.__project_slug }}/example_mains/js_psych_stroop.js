// To use the jsPsych package first install jspsych using `npm install jspsych`
// In this example the html-keyboard-response plugin is used. Install it via `npm install @jspsych/plugin-html-keyboard-response`
// Here is documentation on how to program a jspsych experiment using npm:
// https://www.jspsych.org/7.3/tutorials/hello-world/#option-3-using-npm

import {initJsPsych} from 'jspsych';
import 'jspsych/css/jspsych.css'
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
    const PRE_TRAIN_TRIALS = 10
    const POST_TRAIN_TRIALS = 10

    // key to response mapping (this could be something different based on id for counterbalancing. One could use the
    // remainder of id / 24 to determine the counterbalance condition)
    const keyToResponseMapping = {
        'c': 'red',
        'd': 'blue',
        'n': 'green',
        'j': 'yellow'
    }


    // For convenience, we first define a function that returns a trial (as sequence of fixation, soa, stimulus and feedback)
    const trial = (color, word, phase) => {
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
            type: htmlKeyboardResponse,
            stimulus: `<div style="color: ${color}">${word}</div>`,
            choices: ['c', 'd', 'n', 'j'],
            trial_duration: STIMULUS_DURATION,
            response_ends_trial: true,
            on_finish: function (data) { // here we set the correct (based on response and keymapping) and the phase as entry in the data
                const key = jsPsych.data.getLastTrialData()['trials'][0]['response']
                data['correct'] = keyToResponseMapping[key] === color
                data['phase'] = phase
            }
        })

        // FEEDBACK
        if (phase === 'training') {
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
        }
        return stimulus_timeline

    }

    // Here we set up functions to randomly select words and colors

    // create lists for colors and words
    const colors = ['red', 'green', 'blue', 'yellow']
    const words = ['RED', 'GREEN', 'BLUE', 'YELLOW']

    // get a random color form the list
    const rand_color = () => {
        return colors[Math.floor(Math.random() * colors.length)];
    }

    // get a random word from the list
    const rand_word = () => {
        return words[Math.floor(Math.random() * words.length)];
    }

    // MAKE THE EXPERIMENT TIMELINE

    // Instructions
    let instructions = [
        {
            type: htmlKeyboardResponse,
            stimulus: 'In the following experiment you are asked to name the colors (not the meaning) of the words<br>Press >> Space << to continue',
            choices: [' ']
        }
    ]

    for (let k in keyToResponseMapping) {
        instructions.push({
            type: htmlKeyboardResponse,
            stimulus: `If the color of the word is ${keyToResponseMapping[k]}, press >> ${k} << <br>Press >> ${k} >> to continue`,
            choices: [k]
        })
    }
    instructions.push(
        {
            type: htmlKeyboardResponse,
            stimulus: 'The experiment will start now<br>Press >> Space << to continue',
            choices: [' ']
        }
    )

    // Pre-training
    let pretraining = [];
    for (let i = 0; i < PRE_TRAIN_TRIALS; i++) {
        pretraining = pretraining.concat(trial(rand_color(), rand_word(), 'pre-training'));
    }

    // training. Here we use the condition to set the number of training trials
    let training = [];
    for (let i = 0; i < condition['n_train']; i++) {
        training = training.concat(trial(rand_color(), rand_word(), 'training'));
    }

    // post-training
    let posttraining = []
    for (let i = 0; i < POST_TRAIN_TRIALS; i++) {
        posttraining = posttraining.concat(trial(rand_color(), rand_word(), 'post-training'));
    }

    // a pause trial
    const pause = {
        type: htmlKeyboardResponse,
        stimulus: 'The next block will start now<br>Press >> Space << to continue',
        choices: [' ']
    }

    // this is the timeline: instructions, pretraining, pause, training, pause, posstraining
    const timeline = [...instructions, ...pretraining, ...[pause], ...training, ...[pause], ...posttraining]

    // run the experiment and wait it to finish
    await jsPsych.run(timeline)

    // calculate accuracy before and after training
    const preTrainAcc = jsPsych.data.get().filter({'phase': 'pre-training', 'correct': true}).count() / PRE_TRAIN_TRIALS
    const postTrainAcc = jsPsych.data.get().filter({'phase': 'post-training', 'correct': true}).count() / POST_TRAIN_TRIALS


    // return difference between before and after training as observation
    return JSON.stringify({condition, accuracy_difference: (postTrainAcc - preTrainAcc)})
}


export default main