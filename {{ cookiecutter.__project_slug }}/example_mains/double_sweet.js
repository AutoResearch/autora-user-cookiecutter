import {initJsPsych} from 'jspsych';
import 'jspsych/css/jspsych.css'
import 'sweetbean/dist/style/main.css';
import 'sweetbean/dist/style/bandit.css';
import 'sweetbean/dist/style/touch-buttons.css'
import * as SweetBeanRuntime from 'sweetbean/dist/runtime';

import htmlKeyboardResponse from '@jspsych/plugin-html-keyboard-response';
import jsPsychRok from '@jspsych-contrib/plugin-rok';
import jsPsychExtensionTouchscreenButtons from '@sweet-jspsych/extension-touchscreen-buttons'

global.initJsPsych = initJsPsych;
global.jsPsychHtmlKeyboardResponse = htmlKeyboardResponse
global.jsPsychRok = jsPsychRok
global.jsPsychExtensionTouchscreenButtons = jsPsychExtensionTouchscreenButtons

Object.entries(SweetBeanRuntime).forEach(([key, value]) => {
    global[key] = value;
});

/**
 * This is the main function where you program your experiment. For example, you can install jsPsych via node and
 * use functions from there
 * @param id this is a number between 0 and number of participants. You can use it for example to counterbalance between subjects
 * @param condition this is a condition (for example uploaded to the database with the experiment runner in autora)
 * @returns {Promise<*>} after running the experiment for the subject return the observation in this function, it will be uploaded to autora
 */
const main = async (id, condition) => {
    const observation = await eval(condition['experiment_code'] + "\nrunExperiment();");
    return JSON.stringify(observation)
}


export default main
