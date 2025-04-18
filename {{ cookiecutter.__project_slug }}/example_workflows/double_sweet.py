import json

from autora.variable import VariableCollection, Variable
from autora.experimentalist.random import pool
from autora.experiment_runner.firebase_prolific import firebase_runner
from autora.state import StandardState, on_state, Delta

import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression

from sweetpea import Factor, DerivedLevel, CrossBlock, synthesize_trials, experiments_to_dicts, WithinTrial

from sweetbean.stimulus import Fixation, ROK, Feedback
from sweetbean.variable import FunctionVariable, TimelineVariable
from sweetbean import Block, Experiment
from sweetbean.extension import TouchButton
from sweetbean.util.data_process import process_autora

# *** Set up variables *** #
# TODO: Declare your ivs and dvs here
variables = VariableCollection(
    independent_variables=[
        Variable(name=..., allowed_values=...)
    ],
    dependent_variables=[
        Variable(name=..., value_range=(..., ...))],)

# *** State *** #

state = StandardState(
    variables=variables,
)

# *** Components/Agents *** #
# Components are functions that run on the state. The main components are:
# - theorist
# - experiment-runner
# - experimentalist
# See more about components here: https://autoresearch.github.io/autora/


# ** Theorist ** #
# Here we use a linear regression as theorist, but you can use other theorists included in
# autora (for a list: https://autoresearch.github.io/autora/theorist/)

theorist = LinearRegression()


# To use the theorist on the state object, we wrap it with the on_state functionality and return a
# Delta object.
# Note: The if the input arguments of the theorist_on_state function are state-fields like
# experiment_data, variables, ... , then using this function on a state object will automatically
# use those state fields.
# The output of these functions is always a Delta object. The keyword argument in this case, tells
# the state object witch field to update.


@on_state()
def theorist_on_state(experiment_data, variables):
    ivs = [iv.name for iv in variables.independent_variables]
    dvs = [dv.name for dv in variables.dependent_variables]
    x = experiment_data[ivs]
    y = experiment_data[dvs]
    return Delta(models=[theorist.fit(x, y)])


# ** Experimentalist ** #
# Here, we use a random pool and use the wrapper to create an on state function
# Note: The argument num_samples is not a state field. Instead, we will pass it in when calling
# the function


@on_state()
def experimentalist_on_state(variables, num_samples):
    return Delta(conditions=pool(variables, num_samples))


# ** Experiment Runner ** #
# We will run our experiment on firebase and need credentials. You will find them here:
# (https://console.firebase.google.com/)
#   -> project -> project settings -> service accounts -> generate new private key

with open('firebase_credentials.json') as f:
    firebase_credentials = json.load(f)


# simple experiment runner that runs the experiment on firebase
experiment_runner = firebase_runner(
    firebase_credentials=firebase_credentials,
    time_out=30,
    sleep_time=5)


# Again, we need to wrap the runner to use it on the state. Here, we send the raw conditions.
@on_state()
def runner_on_state(conditions):
    experiments = []
    for _, row in conditions.iterrows():
        # SweetPea - Experiment design

        # TODO: Implement you design here

        design = []
        crossing = []
        constraints = []

        cross_block = CrossBlock(design, crossing, constraints)
        _timelines = synthesize_trials(cross_block, 1)
        timelines = experiments_to_dicts(cross_block, _timelines)


        # SweetPea - Stimulus Sequence

        seq = [
            #TODO: Implement your stimulus sequence here
        ]

        for timline in timelines:
            block = Block(seq, timline)
            experiment = Experiment([block]).to_js_string()
            experiments.append(experiment)

    conditions_to_send = conditions.copy()
    conditions_to_send['experiment_code'] = experiments
    data = experiment_runner(conditions_to_send)
    data = process_autora(data, len(seq))
    df = pd.DataFrame(data)

    # TODO: Implement your data processing here (raw data -> condition, observation pairs)



    # Fill this with ivs and dvs
    summary = pd.DataFrame({


    })

    # TODO: Implement your data processing here (raw data -> condition, observation pairs)
    return Delta(experiment_data=summary)



def report_linear_fit(model: LinearRegression, precision=4):
    coefs = model.coef_.flatten()
    intercept = np.round(model.intercept_, precision)[0]
    terms = []

    for i, coef in enumerate(coefs):
        name = variables.independent_variables[i].name
        rounded_coef = np.round(coef, precision)
        terms.append(f"{rounded_coef}·{name}")

    formula = " + ".join(terms)
    sign = "+" if intercept >= 0 else "-"
    return f"{variables.dependent_variables[0].name} = {formula} {sign} {abs(intercept)}"


# Now, we can run our components
for cycle in range(3):
    print(f'Starting cycle {cycle}')
    state = experimentalist_on_state(state, num_samples=2)  # Collect 2 conditions per iteration
    state = runner_on_state(state)
    state = theorist_on_state(state)
    print(state.experiment_data)
    state.experiment_data.to_csv(f'experiment_data_{cycle}.csv')

    print()
    print('*' * 20)
    print(f'Model in cycle {cycle}:')
    print(report_linear_fit(state.models[-1]))
    print('*' * 20)
    print()
