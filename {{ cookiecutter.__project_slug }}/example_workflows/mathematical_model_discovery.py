"""
Workflow
    Experimentalist: Random Sampling / Falsification Sampling
    Runner: Prolific Firebase Runner
    Theorist: Symbolic Regression
"""
import json

import pandas as pd
import numpy as np
from pathlib import Path

# sweetPea functionality
from sweetpea import (
    Factor, DerivedLevel, WithinTrial,
    Transition, MinimumTrials, CrossBlock,
    synthesize_trials, CMSGen, experiments_to_dicts
)

# pysr for symbolic regression
from pysr import PySRRegressor

# autora core functionality
from autora.variable import Variable, VariableCollection
from autora.state import StandardState, on_state, Delta
from autora.serializer import dump_state

# autora experimentalists
from autora.experimentalist.grid import grid_pool
from autora.experimentalist.random import random_sample
from autora.experimentalist.falsification import falsification_sample

# autora experiment runner
from autora.experiment_runner.firebase_prolific import firebase_prolific_runner

# ** Dependent Variable ** #
congruency_effect = Variable(name='congruency_effect', value_range=(0, 1))

# ** Independent Variables ** #
coherence_movement = Variable(name='coherence_movement', value_range=(0, 1),
                              allowed_values=np.linspace(.01, 1, 100))
coherence_orientation = Variable(name='coherence_orientation', value_range=(0, 1),
                                 allowed_values=np.linspace(.01, 1, 100))

# ** Variable Collection ** #
variables = VariableCollection(dependent_variables=[congruency_effect],
                               independent_variables=[coherence_movement, coherence_orientation])

# *** State *** #
state = StandardState(
    variables=variables,
)

# *** Components *** #
# ** Grid Pooler ** #
grid_pool_on_state = on_state(grid_pool, output=["conditions"])

# ** Random Sampler ** #
random_sample_on_state = on_state(random_sample, output=["conditions"])


# ** Falsification Sampler ** #
@on_state()
def falsification_sample_on_state(conditions, models, experiment_data, variables, num_samples):
    ivs = [v.name for v in variables.independent_variables]
    dvs = [v.name for v in variables.dependent_variables]
    X, y = experiment_data[ivs], experiment_data[dvs]
    return Delta(conditions=falsification_sample(conditions, models[-1], X, y, variables,
                                                 num_samples=num_samples))


# ** Experiment Runner ** ##

def condition_to_trial_sequence(coherence_movement,
                                coherence_orientation,
                                number_blocks=2,
                                minimum_trials=48):
    """
    Function to transform a condition into trial sequences
    """
    direction_movement = Factor('direction_movement', [0, 180])
    direction_orientation = Factor('direction_orientation', [0, 180])

    def is_congruent(dir_mov, dir_or):
        return dir_mov == dir_or

    def is_incongruent(dir_mov, dir_or):
        return not is_congruent(dir_mov, dir_or)

    congruent = DerivedLevel('congruent',
                             WithinTrial(is_congruent,
                                         [direction_movement, direction_orientation])
                             )
    incongruent = DerivedLevel('incongruent',
                               WithinTrial(is_incongruent,
                                           [direction_movement, direction_orientation])
                               )

    congruency = Factor('congruency', [congruent, incongruent])

    def is_transition_cc(cong):
        return cong[-1] == 'congruent' and cong[0] == 'congruent'

    def is_transition_ci(cong):
        return cong[-1] == 'congruent' and cong[0] == 'incongruent'

    def is_transition_ic(cong):
        return cong[-1] == 'incongruent' and cong[0] == 'congruent'

    def is_transition_ii(cong):
        return cong[-1] == 'incongruent' and cong[0] == 'incongruent'

    transition_cc = DerivedLevel('cc', Transition(is_transition_cc, [congruency]))
    transition_ci = DerivedLevel('ci', Transition(is_transition_ci, [congruency]))
    transition_ic = DerivedLevel('ic', Transition(is_transition_ic, [congruency]))
    transition_ii = DerivedLevel('ii', Transition(is_transition_ii, [congruency]))

    congruency_transition = Factor('congruency_transition',
                                   [transition_cc, transition_ci, transition_ic, transition_ii])

    design = [direction_movement, direction_orientation, congruency, congruency_transition]
    crossing = [direction_movement, congruency_transition]
    constraints = [MinimumTrials(minimum_trials)]

    block = CrossBlock(design, crossing, constraints)

    experiments = synthesize_trials(block, number_blocks, CMSGen)

    sequence_list = experiments_to_dicts(block, experiments)
    for sequence in sequence_list:
        for trial in sequence:
            trial['coherence_movement'] = float(coherence_movement)
            trial['coherence_orientation'] = float(coherence_orientation)
    return sequence_list


def trial_list_to_experiment_data(trial_sequence):
    """
    Parse a trial sequence (from jsPsych) into dependent and independent variables
    independent: coherence_movement, coherence_orientation
    dependent: congruency_effect (rt_incongruent - rt_congruent / max_response_time)
    """
    res_dict = {
        'coherence_movement': [],
        'coherence_orientation': [],
        'congruency': [],
        'rt': []
    }
    for trial in trial_sequence:
        # Filter trials that are not ROK (instructions, fixation, ...)
        if trial['trial_type'] != 'rok':
            continue
        # Filter trials with no or incorrect response
        if 'correct' not in trial or not trial['correct']:
            continue
        congruency = trial['coherent_movement_direction'] == trial['coherent_orientation']
        coherence_movement = trial['coherence_movement'] / 100.
        coherence_orientation = trial['coherence_orientation'] / 100.
        rt = trial['rt']
        res_dict['congruency'].append(int(congruency))
        res_dict['coherence_movement'].append(float(coherence_movement))
        res_dict['coherence_orientation'].append(float(coherence_orientation))
        res_dict['rt'].append(float(rt))

    dataframe_raw = pd.DataFrame(res_dict)

    grouped = dataframe_raw.groupby(['coherence_movement', 'coherence_orientation'])

    mean_rt = grouped.apply(lambda x: pd.Series({
        'mean_rt_congruent': x[x['congruency'] == 1]['rt'].mean(),
        'mean_rt_incongruent': x[x['congruency'] == 0]['rt'].mean()
    }, index=['mean_rt_congruent', 'mean_rt_incongruent']), include_groups=False).reset_index()

    # Calculate congruency effect
    mean_rt['congruency_effect'] = (mean_rt['mean_rt_incongruent'] - mean_rt[
        'mean_rt_congruent']) / 2000.
    return mean_rt[['coherence_movement', 'coherence_orientation', 'congruency_effect']]


firebase_credentials = {
    "type": "type",
    "project_id": "project_id",
    "private_key_id": "private_key_id",
    "private_key": "private_key",
    "client_email": "client_email",
    "client_id": "client_id",
    "auth_uri": "auth_uri",
    "token_uri": "token_uri",
    "auth_provider_x509_cert_url": "auth_provider_x509_cert_url",
    "client_x509_cert_url": "client_x509_cert_url"
}

YOUR_PROLIFIC_TOKEN = 'your_token'

experiment_runner = firebase_prolific_runner(
    firebase_credentials=firebase_credentials,
    sleep_time=10,
    study_name='Triangle Chaos',
    study_description='Reaction time experiment in under 1 minute.',
    study_url='your_url',
    study_completion_time=1,
    prolific_token=YOUR_PROLIFIC_TOKEN
)


@on_state()
def runner_on_state(conditions, num_blocks, num_trials):
    trial_sequences = []
    for _, row in conditions.iterrows():
        trial_sequences.append(condition_to_trial_sequence(
            row['coherence_movement'],
            row['coherence_orientation'],
            num_blocks,
            num_trials))

    data_raw = experiment_runner(trial_sequences)

    experiment_data = pd.DataFrame()
    for item in data_raw:
        _lst = json.loads(item)['trials']
        _df = trial_list_to_experiment_data(_lst)
        experiment_data = pd.concat([experiment_data, _df], axis=0)
    return Delta(experiment_data=experiment_data)


# ** Theorist ** #

# The PySRRegressor doesn't use the standard sklearn output format for the predict function, here we adjust this:
class AdjustedPySRRegressor(PySRRegressor):
    def predict(self, X, index=None):
        y = super().predict(X, index)
        if len(y.shape) < 2:
            return np.array([[el] for el in y])
        return y


# We define a set of mathematical operations for the symbolic regression algorithm
binary_operators = ["+", "-", "*", "/", "^"]
unary_operators = ["sin", "cos", "tan", "exp", "log", "sqrt", "abs"]
# Theorists
pysr_regressor = AdjustedPySRRegressor(niterations=100,
                                       binary_operators=["+", "-", "*", "/", "^"],
                                       unary_operators=["cos", "sin", "tan", "exp", "log", "sqrt"],
                                       batching=True,
                                       multithreading=True,
                                       temp_equation_file=False)

# Here, we show how to use the on_state wrapper as decorator. Note, if state fields should be used as input arguments to the wrapped
# function, then the argument names have to align with the field names (here: experiment_data and variables). The same is true for the output
# Delta. Here, `models` is a field of the StandardState
from autora.state import Delta


@on_state()
def pysr_theorist_on_state(experiment_data, variables: VariableCollection):
    ivs = [v.name for v in variables.independent_variables]
    dvs = [v.name for v in variables.dependent_variables]
    X, y = experiment_data[ivs], experiment_data[dvs]
    new_model = pysr_regressor.fit(X, y)
    return Delta(models=[new_model])


state = StandardState(variables=variables)
for cycle in range(4):
    state = grid_pool_on_state(state)
    if not cycle % 2:  # cycle is odd
        state = random_sample_on_state(state, num_samples=3)
    else:  # cycle is even
        state = random_sample_on_state(state, num_samples=100)
        state = falsification_sample_on_state(state, num_samples=3)
    # state = run_firebase_on_state(state, num_blocks=2, num_trials=48)
    state = pysr_theorist_on_state(state)
    dump_state(state, Path('./prolific_state.pkl'))
    print(state.models[-1].sympy())
