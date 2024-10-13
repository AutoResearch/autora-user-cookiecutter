// To use the jsPsych package first install jspsych using `npm install jspsych`
// This example uses the rdk plugin. Install it via `npm install @jspsych-contrib/plugin-rdk`
// This example uses the html-keyboard-response plugin. Install it via `npm install @jspsych/plugin-html-keyboard-response`
// Here is documentation on how to program a jspsych experiment using npm:
// https://www.jspsych.org/7.3/tutorials/hello-world/#option-3-using-npm

import {initJsPsych} from 'jspsych';
import 'jspsych/css/jspsych.css'
import htmlKeyboardResponse from '@jspsych/plugin-html-keyboard-response';
import jsPsychHtmlChoice from '@jspsych-contrib/plugin-html-choice';
import fullscreen from '@jspsych/plugin-fullscreen';
import '../css/slot-machine.css'


/**
 * This is the main function where you program your experiment. Install jsPsych via node and
 * use functions from there
 * @param id this is a number between 0 and number of participants. You can use it for example to counterbalance between subjects
 * @param condition this is a condition (4-32. Here we want to find out how the training length impacts the accuracy in a testing phase)
 * @returns {Promise<*>} the accuracy in the post-trainging phase relative to the pre-training phase
 */
const main = async (id, condition) => {

    const timeline_variables = JSON.parse(condition)
    const nr_trials = timeline_variables.length
    let current_trial = 0

    const jsPsych = initJsPsych({
        show_progress_bar: true,
        auto_update_progress_bar: false,
        on_finish: function () {
            jsPsych.data.displayData();
        }
    });

    // create timeline (enter fullscreen)
    const timeline = [{
        type: fullscreen,
        fullscreen_mode: true
    }];


    // create html divs
    // let sm_blue = '<div style="position: absolute; top:0; left:0" class="slotmachine blue"></div>'
    // let sm_red = '<div style="position: absolute; top:0; right:0" class="slotmachine red"></div>'

    const sm_blue = (pos) => {
        let _pos = 'left: 0'
        if (pos === 'right') {
            _pos = 'right: 0'
        }
        return `<div style="position: absolute; top:10vh; height: 60vh; ${_pos}" class="slotmachine blue"></div>`
    }
    const sm_red = (pos) => {
        let _pos = 'left: 0'
        if (pos === 'right') {
            _pos = 'right: 0'
        }
        return `<div style="position: absolute; top:10vh; height: 60vh; ${_pos}" class="slotmachine red"></div>`
    }
    let score = 0

    const test = {
        timeline: [
            {
                type: jsPsychHtmlChoice,
                html_array: () => {
                    return [
                        sm_blue(jsPsych.timelineVariable('pos')[0]),
                        sm_red(jsPsych.timelineVariable('pos')[1])
                    ]
                },
                on_load: () => {
                    let content = document.getElementById('jspsych-content')
                    let score_div = document.createElement('div')
                    score_div.style.position = 'fixed'
                    score_div.style.left = '50vw'
                    score_div.style.bottom = '3vh'
                    score_div.style.transform = 'translateX(-50%)'
                    score_div.innerText = `Score: ${score} of ${nr_trials}`
                    content.appendChild(score_div)
                },
                trial_duration: null,
                values: jsPsych.timelineVariable('values'),
                response_ends_trial: true,
                time_after_response: 800,
                on_finish: (data) => {
                    current_trial += 1
                    score += data.value
                    let progress = current_trial / nr_trials
                    jsPsych.setProgressBar(progress)
                }
            },
            {
                type: htmlKeyboardResponse,
                stimulus: '',
                trial_duration: 100,
                on_load: () => {
                    let content = document.getElementById('jspsych-content')
                    let score_div = document.createElement('div')
                    score_div.style.position = 'fixed'
                    score_div.style.left = '50vw'
                    score_div.style.bottom = '3vh'
                    score_div.innerText = `Score: ${score} of ${nr_trials}`
                    score_div.style.transform = 'translateX(-50%)'
                    content.appendChild(score_div)
                },
            },
        ],
        timeline_variables: timeline_variables
    }

    timeline.push(test)

    await jsPsych.run(timeline)

    const observation = jsPsych.data.get().filter({trial_type: "html-choice"}).select('response')
    return JSON.stringify({condition: condition, observation: observation})
}


export default main